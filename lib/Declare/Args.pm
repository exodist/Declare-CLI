package Declare::Args;
use strict;
use warnings;

our $VERSION = "0.001";

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

    croak "arg '$name' already defined"
        if $self->args->{$name};

    for my $prop ( keys %config ) {
        next if $prop =~ m/^(alias|list|bool|default|check|transform)$/;
        croak "invalid arg property: '$prop'";
    }

    $config{name} = $name;

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

        $config{_alias} = { map { $_ => 1 } @$aliases };

        for my $alias ( @$aliases ) {
            croak "Cannot use alias '$alias', name is already taken by another arg."
                if $self->args->{$alias};

            $self->args->{$alias} = \%config;
        }
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

    my %matches = map { $self->args->{$_}->{name} => 1 }
        grep { m/^$key/ }
            keys %{ $self->args };
    my @matches = keys %matches;

    die "argument '$key' is ambiguous, could be: " . join( ", " => @matches ) . "\n"
        if @matches > 1;

    die "unknown argument '$key'\n"
        unless @matches;

    return $matches[0];
}

1;

__END__

=pod

=head1 NAME

Declare::Args - Simple and Sane Command Line Argument processing

=head1 DESCRIPTION

Declare-Args is a sane and declarative way to define and consume command line
arguments. Any number of dashes can be used, it is not picky about -arg or
--arg. You can use '-arg value' or '-arg=value', it will just work. Shortest
unambiguous substring of any arg name can be used to specify the argument.

=head1 SYNOPSIS

=head2 DECLARATIVE

Code:

    #!/usr/bin/env perl
    use Declare::Args;

    # Define a simple arg, any value works:
    arg 'simple';

    # Define a boolean arg
    arg with_x => ( bool => 1 );

    # Define a boolean that is on unless specified
    arg with_y => ( bool => 1, default => 1 );

    # Define an arg that can have multiple values:
    arg items => ( list => 1 );

    # Define an arg with a default (if arg is not specified default is used)
    arg compiler => ( default => 'gcc' );

    # Define an arg with validation (see 'check' section for more builtins)
    arg my_number => ( check => 'number' );

    # Define more complex validation
    arg phone => ( check => sub { my $val = shift; ... });
    arg name  => ( check => qr/^[A-Z]\w+$/ );

    # Convert the value
    arg double => ( transform => sub { $_[0] * 2 } );

    # Aliases can be added:
    arg nameA  => ( alias => 'nameB' );
    arg otherA => ( alias => [ 'otherA', 'otherB' ]);

    ########################
    # Now process some args:
    my ( $list, $args ) = parse_args( @ARGV );

    # $list contains the items from @ARGV that are not specified args (or their values)
    # $args is a hashref containing the args and their values.

Command Line:

    ./my_command.pl -simple simple_value -with_x --items "a,b, c" -phone="555-555-5555" --double=5

The shortest unambiguous string can be used for each parameter. For instance we
only have one argument defined above that starts with 's', that is 'simple':

    ./my_command.pl -s simple_value

=head2 OBJECT ORIENTED

=head1 ARGUMENT PROPERTIES

=over 4

=back

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2012 Chad Granum

Declare-Args is free software; Standard perl licence.

Declare-Args is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the license for more details.
