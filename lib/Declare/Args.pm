package Declare::Args;
use strict;
use warnings;

use Carp qw/croak/;

use Exporter::Declare qw{
    import
    gen_default_export
    default_export
};

gen_default_export 'ARGS_META' => sub {
    my ( $class, $caller ) = @_;
    my $meta = $class->new( $caller );
    return sub { $meta };
};

default_export arg        => sub { caller->ARGS_META->arg( @_ )   };
default_export parse_args => sub { caller->ARGS_META->parse( @_ ) };

sub class   { shift->{class}   }
sub args    { shift->{args}    }
sub default { shift->{default} }

sub new {
    my $class = shift;
    my ( $caller ) = @_;
    return bless { class => $caller, args => {}, default => {} } => $class;
}

sub arg {
    my $self = shift;
    my ( $name, %config ) = @_;

    for my $prop ( keys %config ) {
        next if $prop =~ m/^(alias|list|bool|default|check|transform)$/;
        croak "invalid arg property: '$prop'";
    }

    croak "'check' cannot be used with 'bool'"
        if $config{bool} && $config{check};

    croak "'transform' cannot be used with 'bool'"
        if $config{bool} && $config{transform};

    croak "arg properties 'list' and 'bool' are mutually exclusive"
        if $config{list} && $config{bool};

    $self->default->{$name} = $config{default}
        if exists $config{default};

    if ( exists $config{check} ) {
        my $ref = ref $config{check};
        croak "'$config{check}' is not a valid value for 'check'"
            if ($ref && $ref !~ m/^(CODE|Regexp)$/)
            || (!$ref && $config{check} !~ m/^(file|dir|number)$/);
    }

    if ( exists $config{alias} ) {
        my $aliases = ref $config{alias} ?   $config{alias}
                                         : [ $config{alias} ];

        $config{_alias} = { map { $_ => 1 } @$aliases }
    }

    $self->args->{$name} = \%config;
}

sub parse {
    my $self = shift;
    my @args = @_;

    my $params = [];
    my $flags  = { %{ $self->default } };
    my $no_flags = 0;

    while ( my $arg = shift @args ) {
        if ( $arg eq '--' ) {
            $no_flags++;
        }
        elsif ( $arg =~ m/^-+([^-=]+)(?:=(.+))?$/ && !$no_flags ) {
            my ( $key, $value ) = ( $1, $2 );

            my $name = $self->_flag_name( $key );
            my $values = $self->_flag_value(
                $name,
                $value,
                \@args
            );

            if( $self->args->{$name}->{list} ) {
                push @{$flags->{$name}} => @$values;
            }
            else {
                $flags->{$name} = $values->[0];
            }
        }
        else {
            push @$params => $arg;
        }
    }

    return ( $params, $flags );
}

sub _flag_value {
    my $self = shift;
    my ( $flag, $value, $args ) = @_;

    my $spec = $self->args->{$flag};

    if ( $spec->{bool} ) {
        return [$value] if defined $value;
        return [!$spec->{default} ? 1 : 0];
    }

    my $val = defined $value ? $value : shift @$args;

    my $out = $spec->{list} ? [ split /\s*,\s*/, $val ]
                            : [ $val ];

    $self->_validate( $flag, $spec, $out );

    return $out unless $spec->{transform};
    return [ map { $spec->{transform}->($_) } @$out ];
}

sub _validate {
    my $self = shift;
    my ( $flag, $spec, $value ) = @_;

    my $check = $spec->{check};
    return unless $check;
    my $ref = ref $check || "";

    my @bad;

    if ( $ref eq 'Regexp' ) {
        @bad = grep { $_ !~ $check } @$value;
    }
    elsif ( $ref eq 'CODE' ) {
        @bad = grep { !$check->( $_ ) } @$value;
    }
    elsif ( $check eq 'file' ) {
        @bad = grep { ! -f $_ } @$value;
    }
    elsif ( $check eq 'dir' ) {
        @bad = grep { ! -d $_ } @$value;
    }
    elsif ( $check eq 'number' ) {
        @bad = grep { m/\D/ } @$value;
    }

    return unless @bad;
    my $type = $ref || $check;
    die "Validation Failed for '$flag=$type': " . join( ", ", @bad ) . "\n";
}

sub _flag_name {
    my $self = shift;
    my ( $key ) = @_;

    my @matches = grep {
        $self->args->{$_}->{_alias}->{$key} || m/^$key/
    } keys %{ $self->args };

    die "argument '$key' is ambiguous, could be: " . join( ", " => @matches ) . "\n"
        if @matches > 1;

    die "unknown argument '$key'\n"
        unless @matches;

    return $matches[0];
}

1;

