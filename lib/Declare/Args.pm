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
    my $meta = $class->new();
    $meta->{class} = $caller;
    return sub { $meta };
};

default_export arg        => sub { caller->ARGS_META->arg( @_ )   };
default_export parse_args => sub { caller->ARGS_META->parse( @_ ) };
default_export arg_info   => sub { caller->ARGS_META->info        };

sub class   { shift->{class}   }
sub args    { shift->{args}    }
sub default { shift->{default} }

sub new {
    my $class = shift;
    my ( %args ) = @_;

    my $self = bless { args => {}, default => {} } => $class;
    $self->arg( $_, $args{$_} ) for keys %args;

    return $self;
}

sub valid_arg_params {
    return qr/^(alias|list|bool|default|check|transform|description)$/;
}

sub arg {
    my $self = shift;
    my ( $name, %config ) = @_;

    croak "arg '$name' already defined"
        if $self->args->{$name};

    for my $prop ( keys %config ) {
        next if $prop =~ $self->valid_arg_params;
        croak "invalid arg property: '$prop'";
    }

    $config{name} = $name;

    croak "'check' cannot be used with 'bool'"
        if $config{bool} && $config{check};

    croak "'transform' cannot be used with 'bool'"
        if $config{bool} && $config{transform};

    croak "arg properties 'list' and 'bool' are mutually exclusive"
        if $config{list} && $config{bool};

    if (exists $config{default}) {
        croak "References cannot be used in default, wrap them in a sub."
            if ref $config{default} && ref $config{default} ne 'CODE';
        $self->default->{$name} = $config{default};
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
    my $flags = {};
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

    # Add defaults for args not provided
    for my $arg ( keys %{ $self->default } ) {
        next if exists $flags->{$arg};
        my $val = $self->default->{$arg};
        $flags->{$arg} = ref $val ? $val->() : $val;
    }

    return ( $params, $flags );
}

sub info {
    my $self = shift;
    return {
        map { $self->args->{$_}->{name} => $self->args->{$_}->{description} || "No Description" }
            keys %{ $self->args }
    };
}

sub _flag_value {
    my $self = shift;
    my ( $flag, $value, $args ) = @_;

    my $spec = $self->args->{$flag};

    if ( $spec->{bool} ) {
        return [$value] if defined $value;
        return [$spec->{default} ? 0 : 1];
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

    # Exact match
    return $self->args->{$key}->{name}
        if $self->args->{$key};

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

    # Define a list
    arg items => ( list => 1 );

    # Other Options
    arg complex => (
        alias       => $name_or_array_of_names,
        default     => $val_or_sub,
        check       => $bultin_regex_or_sub,
        transform   => sub { my $arg = shift; ...; return $arg },
        description => "This is a complex argument",
    );

    # Get the (args => descriptions) hash, useful for a help() function
    my $info = arg_info();

    #########################
    # Now process some args #
    #########################

    my ( $list, $args ) = parse_args( @ARGV );

    # $list contains the items from @ARGV that are not specified args (or their
    # values)
    # $args is a hashref containing the args and their values.


Command Line:

    ./my_command.pl -simple simple_value -with_x --items "a,b, c"

The shortest unambiguous string can be used for each parameter. For instance we
only have one argument defined above that starts with 's', that is 'simple':

    ./my_command.pl -s simple_value

=head2 OBJECT ORIENTED

    require Declare::Args;

    # Create
    my $args = Declare::Args->new( %args );

    # Add an arg
    $args->arg( $name, %config );

    # Get info
    my $info = $args->info;

    # Parse some args
    my ( $list, $arg_hash ) = $args->parse( @ARGV );

=head1 META OBJECT

When you import Declare::Args a meta-object is created in your package. The
meta object can be accessed via the ARGS_META() method/function. This object is
an instance of Declare::Args and can be manipulated just like any Declare::Args
object.

=head1 EXPORTS

=over 4

=item arg( $name, %config );

=item arg name => ( %config );

Define an argument

=item my $info = arg_info();

Get a ( name => description ) hashref for use in help output.

=item my ( $list, $args ) = parse_args( @ARGS );

Parse some arguments. $list contains the arguments leftovers (those that do not
start with '-'), $args is a hashref containing the values of all the dashed
args.

=back

=head1 METHODS

=over 4

=item $class->new( %args );

Create a new instance.

=item my $class = $args->class;

If the object was created as a meta-object this will contain the class to which
it applies. When created directly this will always be empty.

=item $args->arg( $name, %config );

Define an argument

=item my $info = $args->info();

Get a ( name => description ) hashref for use in help output.

=item my ( $list, $args ) = $args->parse( @ARGS );

Parse some arguments. $list contains the arguments leftovers (those that do not
start with '-'), $args is a hashref containing the values of all the dashed
args.

=back

=head1 ARGUMENT PROPERTIES

=over 4

=item alias => $name

=item alias => [ $name1, $name2 ]

Set aliases for the argument.

=item list => $true_or_false

If true, the argument can be provided on the command line any number of times,
and comma seperated lists will be split for you.

=item bool => $true_or_false

If true, the argument does not require a value and turns the option on or off.
A value can be specified using the '--arg=VAL' format. However '--arg val' will
not treat 'val' as the argument value.

=item default => $scalar

=item default => sub { ... }

Set the default value. If the arg is not specified on the command line this
value will be used. If the value is not a simple scalar it must be wrapped in a
code block.

=item check => 'builtin'

=item check => qr/.../

=item check => sub { my $val = shift; ...; return $bool }

Used to validate argument values. Can be a coderef, a regexp, or one of these bultins:

    'number'    The value(s) must be numeric (only contains digit characters)
    'file'      The value(s) must be a file (uses -f check)
    'dir'       The value(s) must be a directory (-d check)

=item transform => sub { my $orig = shift; ...; return $new }

Function to transform the provided value into something else. Applies to eahc
item of a list when list is true.

=item description => $description_string

Used to describe an argument, useful for help() output.

=back

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2012 Chad Granum

Declare-Args is free software; Standard perl licence.

Declare-Args is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the license for more details.

