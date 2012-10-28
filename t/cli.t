package Declare::CLI::Test;
use strict;
use warnings;
use Fennec;

use Scalar::Util qw/blessed/;

my $CLASS;
BEGIN {
    $CLASS = 'Declare::CLI';
    use_ok $CLASS;
}

sub opts { shift->{opts} };
sub set_opts {
    my $self = shift;
    ($self->{opts}) = @_;
}

can_ok( __PACKAGE__, qw/ CLI_META opt arg process_cli usage / );
isa_ok( CLI_META(), $CLASS );
is( CLI_META->class, __PACKAGE__, "correct class" );
is_deeply( CLI_META->opts, {}, "no opts yet" );
is_deeply( CLI_META->args, {}, "no args yet" );

tests simple => sub {
    my $self = shift;
    my $order = 1;
    my $saw = {};
    opt 'foo';
    opt 'bar';
    opt 'baz';
    arg '-tub' => sub { $saw->{tub}  = $order++ };
    arg 'blug' => sub {
        is( $_[0], $self, "got self" );
        is( $_[1], 'blug', "got this arg" );
        is_deeply( $_[2], { foo => 'zoot', bar => 'a', baz => 'b' }, "got opts" );
        $saw->{blug} = $order++
    };

    $self->process_cli(
        '--foo=zoot',
        '-bar' => 'a',
        '--baz' => 'b',
        '--',
        '-tub',
        'blug'
    );

    is_deeply( $saw, { tub => 1, blug => 2 }, "Args handled properly" );
    is_deeply( $self->opts, { foo => 'zoot', bar => 'a', baz => 'b' }, "got opts" );

    ok( !eval { $self->process_cli( '-b' => 'xxx' ); 1 }, "Ambiguity" );
    like( $@, qr/option 'b' is ambiguous, could be: bar, baz/, "Ambiguity Message" );

    ok( !eval { $self->process_cli( '-x' => 'xxx' ); 1 }, "Invalid" );
    like( $@, qr/unknown option 'x'/, "Invalid Message" );
};

tests usage => sub {
    my $self = shift;

    opt 'nodesc';
    opt foo => ( description => "this is foo" );
    opt bool => ( bool => 1, description => 'this is bool' );
    opt list => ( list => 1, description => 'this is list' );
    opt longer => ( description => 'this is longer' );

    arg one => sub { 1 };
    arg two => sub { 2 };
    arg three => ( handler => sub { 3 }, description => 'is three' );

    is( $self->usage, <<"    EOT", "Get usage" );
Options:
    -bool              this is bool
    -foo    XXX        this is foo
    -list   XXX,...    this is list
    -longer XXX        this is longer
    -nodesc XXX        No Description.

Commands:
    one      No Description.
    three    is three
    two      No Description.

    EOT
};

1;

__END__

tests complex => sub {
    opt foo => ( bool => 1 );
    opt bar => ( list => 1 );
    opt baz => ( alias => 'zag' );
    opt buz => ( bool => 1, default => 1 );
    opt tin => ( default => 'fred', alias => ['tinn', 'tinnn'] );

    ok( !eval { opt boot => ( bool => 1, list => 1 ); 1 }, "invalid props" );
    like( $@, qr/opt properties 'list' and 'bool' are mutually exclusive/, "invalid prop message" );

    my ( $args, $opts ) = parse_opts(
        '-f',
        '--bar' => 'a,b,c, d , e',
        '-bar=1, 2 ,3',
        '-zag=b',
        '--',
        '-tub',
        'blug'
    );

    is_deeply( $args, ['-tub', 'blug'], "Got params" );
    is_deeply(
        $opts,
        {
            foo => 1,
            bar => [qw/a b c d e 1 2 3/],
            baz => 'b',
            buz => 1,
            tin => 'fred'
        },
        "got flags"
    );

    ( $args, $opts ) = parse_opts(
        '-f=0',
        '-buz',
        '--tinnn',
        "din dan"
    );

    is_deeply( $args, [], "Got params" );
    is_deeply(
        $opts,
        {
            foo => 0,
            buz => 0,
            tin => 'din dan'
        },
        "change default"
    );
};

tests validation => sub {
    opt code   => ( check => sub { $_[0] eq 'food' });
    opt number => ( check => 'number', list => 1    );
    opt dir    => ( check => 'dir',    list => 1    );
    opt regex  => ( check => qr/^AAA/               );
    opt file   => ( check => 'file'                 );

    ok( !eval { opt bad1 => ( check => "foo" ); 1 }, "invalid check (string)" );
    like( $@, qr/'foo' is not a valid value for 'check'/, "invalid check message" );

    ok( !eval { opt bad2 => ( check => []    ); 1 }, "invalid check (ref)" );
    like( $@, qr/'ARRAY\(0x[\da-fA-F]*\)' is not a valid value for 'check'/, "invalid check message" );

    lives_ok { parse_opts(
        '-code=food',
        '--regex' => 'AAA Whatever',
        '-number' => '100, 22, 3435',
        '-file'   => __FILE__,
        '-dir'    => '., ..',
    ) } "Valid opts";

    ok( !eval { parse_opts( '--code=tub' ); 1 }, "fail check (code)" );
    like( $@, qr/Validation Failed for 'code=CODE': tub/, "fail check message (code)" );

    ok( !eval { parse_opts( '-regex' => 'Whatever' ); 1 }, "fail check (regex)" );
    like( $@, qr/Validation Failed for 'regex=Regexp': Whatever/, "fail check message (regex)" );

    ok( !eval { parse_opts( '--number' => 'a,b,1,2'); 1 }, "fail check (number)" );
    like( $@, qr/Validation Failed for 'number=number': a, b/, "fail check message (number)" );

    ok( !eval { parse_opts( '-file' => '/Some/Fake/File' ); 1 }, "fail check (file)" );
    like( $@, qr{Validation Failed for 'file=file': /Some/Fake/File}, "fail check message (file)" );

    ok( !eval { parse_opts( '-dir' => '/Some/Fake/Dir,/Another/Fake/Dir,.,..' ); 1 }, "fail check (dir)" );
    like( $@, qr{Validation Failed for 'dir=dir': /Some/Fake/Dir, /Another/Fake/Dir}, "fail check message (dir)" );
};

tests transform => sub {
    opt add5 => ( transform => sub { $_[0] + 5 }, check => 'number' );
    opt add6 => ( transform => sub { $_[0] + 6 }, check => 'number', list => 1 );

    my ( $args, $opts ) = parse_opts(
        '-add5' => '5',
        '-add6' => '1,2,3',
        '--',
        '-tub',
        'blug'
    );

    is_deeply( $args, ['-tub', 'blug'], "Got params" );
    is_deeply(
        $opts,
        {
            add5 => 10,
            add6 => [ 7, 8 ,9 ],
        },
        "got flags"
    );
};

1;

