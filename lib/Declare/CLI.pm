package Declare::CLI;
use strict;
use warnings;

use Carp qw/croak/;
use Scalar::Util qw/blessed/;
use List::Util qw/max/;

use Exporter::Declare qw{
    import
    gen_default_export
    default_export
};

our $VERSION = 0.005;

gen_default_export CLI_META => sub {
    my ( $class, $caller ) = @_;
    my $meta = $class->new();
    $meta->{class} = $caller;
    return sub { $meta };
};

default_export arg => sub {
    my ( $meta, @params ) = parse_params( @_ );
    $meta->add_arg( @params );
};

default_export opt => sub {
    my ( $meta, @params ) = parse_params( @_ );
    $meta->add_opt( @params );
};

default_export usage => sub {
    my ( $meta, @params ) = parse_params( @_ );
    $meta->usage( @params );
};

default_export process_cli => sub {
    my $consumer = shift;
    my ( @cli ) = @_;
    my $meta = $consumer->CLI_META;
    return $meta->process_cli( $consumer, @cli );
};

sub parse_params {
    my ($first, @params) = @_;

    my $ref = ref $first;
    my $type = blessed $first;

    return ( $first->CLI_META, @params )
        if ($type || !$ref) && eval { $first->can( 'CLI_META' ) };

    my $meta = eval { caller(2)->CLI_META };
    croak "Could not find meta data object: $@"
        unless $meta;

    return ( $meta, @_ );
}

sub class { shift->{class} }
sub args { shift->{args}  }
sub opts { shift->{opts}  }
sub _defaults { shift->{defaults}  }

sub new {
    my $class = shift;
    my %params = @_;
    my $self = bless { args => {}, opts => {}, defaults => {} } => $class;

    $self->add_arg( $_ => $params{args}->{$_} )
        for keys %{ $params{args} || {} };

    $self->add_arg( $_ => $params{opts}->{$_} )
        for keys %{ $params{opts} || {} };

    return $self;
}

sub valid_arg_params {
    return qr/^(alias|description|handler)$/;
}

sub add_arg {
    my $self = shift;
    my ( $name, @params ) = @_;
    my %config = @params > 1 ? @params : (handler => $params[0]);

    croak "arg '$name' already defined"
        if $self->args->{$name};

    for my $prop ( keys %config ) {
        next if $prop =~ $self->valid_arg_params;
        croak "invalid arg property: '$prop'";
    }

    $config{name} = $name;
    $config{description} ||= "No Description.";

    croak "You must provide a handler"
        unless $config{handler};

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

sub valid_opt_params {
    return qr/^(alias|list|bool|default|check|transform|description|trigger)$/;
}

sub add_opt {
    my $self = shift;
    my ( $name, %config ) = @_;

    croak "opt '$name' already defined"
        if $self->opts->{$name};

    for my $prop ( keys %config ) {
        next if $prop =~ $self->valid_opt_params;
        croak "invalid opt property: '$prop'";
    }

    $config{name} = $name;
    $config{description} ||= "No Description.";

    croak "'check' cannot be used with 'bool'"
        if $config{bool} && $config{check};

    croak "'transform' cannot be used with 'bool'"
        if $config{bool} && $config{transform};

    croak "opt properties 'list' and 'bool' are mutually exclusive"
        if $config{list} && $config{bool};

    if (exists $config{default}) {
        croak "References cannot be used in default, wrap them in a sub."
            if ref $config{default} && ref $config{default} ne 'CODE';
        $self->_defaults->{$name} = $config{default};
    }

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
            croak "Cannot use alias '$alias', name is already taken by another opt."
                if $self->opts->{$alias};

            $self->opts->{$alias} = \%config;
        }
    }

    $self->opts->{$name} = \%config;
}

sub process_cli {
    my $self = shift;
    my ( $consumer, @cli ) = @_;

    my ( $opts, $args ) = $self->parse_cli( $consumer, @cli );

    # Add defaults for opts not provided
    for my $opt ( keys %{ $self->_defaults } ) {
        next if exists $opts->{$opt};
        my $val = $self->_defaults->{$opt};
        $opts->{$opt} = ref $val ? $val->() : $val;
    }

    # Validate
    $self->_validate( $_, $opts->{$_} )
        for keys %$opts;

    # Trigger
    for my $opt ( keys %$opts ) {
        my $trigger = $self->opts->{$opt}->{trigger};
        next unless $trigger;
        $consumer->$trigger( $opt, $opts->{$opt}, $opts );
    }

    $consumer->set_opts( $opts ) if $consumer->can( 'set_opts' );

    # Process args
    for my $arg ( @$args ) {
        my $handler = $self->args->{$arg}->{handler};
        $consumer->$handler( $arg, $opts );
    }

    return 1;
}

sub parse_cli {
    my $self = shift;
    my ( $consumer, @cli ) = @_;

    my $args = [];
    my $opts = {};
    my $no_opts = 0;

    while ( my $item = shift @cli ) {
        if ( $item eq '--' ) {
            $no_opts++;
        }
        elsif ( $item =~ m/^-+([^-=]+)(?:=(.+))?$/ && !$no_opts ) {
            my ( $key, $value ) = ( $1, $2 );

            my $name = $self->_item_name( $self->opts, $key );
            $value = $self->_opt_value(
                $name,
                $value,
                \@cli
            );

            if( $self->opts->{$name}->{list} ) {
                push @{$opts->{$name}} => @$value;
            }
            else {
                $opts->{$name} = $value;
            }
        }
        else {
            push @$args => $self->_item_name( $self->args, $item );
        }
    }

    return ( $opts, $args );
}

sub _opt_value {
    my $self = shift;
    my ( $opt, $value, $cli ) = @_;

    my $spec = $self->opts->{$opt};

    if ( $spec->{bool} ) {
        return $value if defined $value;
        return $spec->{default} ? 0 : 1;
    }

    my $val = defined $value ? $value : shift @$cli;

    return $spec->{list} ? [ split /\s*,\s*/, $val ]
                         : $val;
}

sub _validate {
    my $self = shift;
    my ( $opt, $value ) = @_;
    my $spec = $self->opts->{$opt};

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
    die "Validation Failed for '$opt=$type': " . join( ", ", @bad ) . "\n";
}

sub _item_name {
    my $self = shift;
    my ( $hash, $key ) = @_;

    # Exact match
    return $hash->{$key}->{name}
        if $hash->{$key};

    my %matches = map { $hash->{$_}->{name} => 1 }
        grep { m/^$key/ }
            keys %{ $hash };
    my @matches = keys %matches;

    die "partial option '$key' is ambiguous, could be: " . join( ", " => @matches ) . "\n"
        if @matches > 1;

    die "unknown option '$key'\n"
        unless @matches;

    return $matches[0];
}

sub usage {
    my $self = shift;

    my $arg_len = max map { length $_ } keys %{ $self->args };
    my $opt_len = max map { length $_ } keys %{ $self->opts };

    my %seen;
    my $opts = join "\n" => sort map {
        my $spec = $self->opts->{$_};
        my $name = $spec->{name};
        my $value = $spec->{bool} ? "" : $spec->{list} ? "XXX,..." : "XXX";

        $seen{$name}++ ? () : sprintf(
            "    -%-${opt_len}s %-7s    %s",
            $name,
            $value,
            $spec->{description}
        );
    } keys %{ $self->opts };

    %seen = ();
    my $cmds = join "\n" => sort map {
        my $spec = $self->args->{$_};
        my $name = $spec->{name};

        $seen{$name}++ ? () : sprintf(
            "    %-${arg_len}s    %s",
            $name,
            $spec->{description}
        );
    } keys %{ $self->args };

    return <<"    EOT";
Options:
$opts

Commands:
$cmds

    EOT
}

1;

__END__

=pod

=head1 NAME

Declare::CLI - Declarative CLI definition.

=head1 DESCRIPTION

This will tie together L<Declare::Opts> and L<Declare::Args>.

=cut
