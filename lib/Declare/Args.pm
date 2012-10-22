package Declare::Args;
use strict;
use warnings;

our $VERSION = "0.003";

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

default_export arg      => sub { caller->ARGS_META->arg( @_ )   };
default_export arg_info => sub { caller->ARGS_META->info        };

sub class { shift->{class}   }
sub args  { shift->{args}    }

sub new {
    my $class = shift;
    my ( %args ) = @_;

    my $self = bless { args => {} } => $class;
    $self->arg( $_, $args{$_} ) for keys %args;

    return $self;
}

sub valid_arg_params {
    return qr/^(alias|run|description)$/;
}

sub arg {
    my $self = shift;
    my ( $name, %config );
    if ( @_ == 2 ) {
        ( $name, $config{run} ) = @_;
    }
    else {
        ( $name, %config ) = @_;
    }

    croak "arg '$name' already defined"
        if $self->args->{$name};

    for my $prop ( keys %config ) {
        next if $prop =~ $self->valid_arg_params;
        croak "invalid arg property: '$prop'";
    }

    $config{name} = $name;
    $config{run} ||= $name;

    croak "'run' parameter must be a codref, or sub name"
        if ref $config{run}
        && ref $config{run} ne 'CODE';

    unless ( ref $config{run} ) {
        croak "Subroutine name is only supported on meta-object"
            unless $self->class;
        $config{run} = $self->class->can( $config{run} );
    }

    croak "arg '$name' requires a 'run' parameter"
        unless $config{run};

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

sub info {
    my $self = shift;
    return {
        map { $self->args->{$_}->{name} => $self->args->{$_}->{description} || "No Description" }
            keys %{ $self->args }
    };
}

sub run {
    my $self = shift;
    my ( $args, $opts ) = @_;

    # Run the arg (find it if partial unambiguous name is given)
}

1;

__END__

=pod

=head1 NAME

Declare::Args - Deprecated, see L<Declare::Opts>

=head1 DESCRIPTION

Deprecated, see L<Declare::Opts>. This module was created because of a
terminology mistake. It will likely be replaced soon with new functionality.
The existing functionality can now be found in Declare::Opts

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2012 Chad Granum

Declare-Args is free software; Standard perl licence.

Declare-Args is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the license for more details.

