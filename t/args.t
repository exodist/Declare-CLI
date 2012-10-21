package Declare::Args::Test;
use strict;
use warnings;
use Fennec;

my $CLASS;
BEGIN {
    $CLASS = 'Declare::Args';
    use_ok $CLASS;
}

tests load => sub {
    can_ok( __PACKAGE__, qw/ ARGS_META arg parse_args/ );
    isa_ok( ARGS_META(), $CLASS );

    is( ARGS_META->class, __PACKAGE__, "correct class" );
    is_deeply( ARGS_META->args, {}, "no args yet" );
};

tests simple => sub {
    arg 'foo';
    arg 'bar';
    arg 'baz';

    my ( $params, $flags ) = parse_args(
        '--foo=zoot',
        '-bar' => 'a',
        '--baz' => 'b',
        '--',
        '-tub',
        'blug'
    );

    is_deeply( $params, ['-tub', 'blug'], "Got params" );
    is_deeply( $flags, { foo => 'zoot', bar => 'a', baz => 'b' }, "got flags" );

    ok( !eval { parse_args( '-b' => 'xxx' ); 1 }, "Ambiguity" );
    like( $@, qr/argument 'b' is ambiguous, could be: bar, baz/, "Ambiguity Message" );

    ok( !eval { parse_args( '-x' => 'xxx' ); 1 }, "Invalid" );
    like( $@, qr/unknown argument 'x'/, "Invalid Message" );
};

tests complex => sub {
    arg foo => ( bool => 1 );
    arg bar => ( list => 1 );
    arg baz => ( alias => 'zag' );
    arg buz => ( bool => 1, default => 1 );
    arg tin => ( default => 'fred', alias => ['tinn', 'tinnn'] );

    ok( !eval { arg boot => ( bool => 1, list => 1 ); 1 }, "invalid props" );
    like( $@, qr/arg properties 'list' and 'bool' are mutually exclusive/, "invalid prop message" );

    my ( $params, $flags ) = parse_args(
        '-f',
        '--bar' => 'a,b,c, d , e',
        '-bar=1, 2 ,3',
        '-zag=b',
        '--',
        '-tub',
        'blug'
    );

    is_deeply( $params, ['-tub', 'blug'], "Got params" );
    is_deeply(
        $flags,
        {
            foo => 1,
            bar => [qw/a b c d e 1 2 3/],
            baz => 'b',
            buz => 1,
            tin => 'fred'
        },
        "got flags"
    );

    ( $params, $flags ) = parse_args(
        '-f=0',
        '-buz',
        '--tinnn',
        "din dan"
    );

    is_deeply( $params, [], "Got params" );
    is_deeply(
        $flags,
        {
            foo => 0,
            buz => 0,
            tin => 'din dan'
        },
        "change default"
    );
};

tests validation => sub {
    arg code   => ( check => sub { $_[0] eq 'food' });
    arg number => ( check => 'number', list => 1    );
    arg dir    => ( check => 'dir',    list => 1    );
    arg regex  => ( check => qr/^AAA/               );
    arg file   => ( check => 'file'                 );

    ok( !eval { arg bad1 => ( check => "foo" ); 1 }, "invalid check (string)" );
    like( $@, qr/'foo' is not a valid value for 'check'/, "invalid check message" );

    ok( !eval { arg bad2 => ( check => []    ); 1 }, "invalid check (ref)" );
    like( $@, qr/'ARRAY\(0x[\da-fA-F]*\)' is not a valid value for 'check'/, "invalid check message" );

    lives_ok { parse_args(
        '-code=food',
        '--regex' => 'AAA Whatever',
        '-number' => '100, 22, 3435',
        '-file'   => __FILE__,
        '-dir'    => '., ..',
    ) } "Valid args";

    ok( !eval { parse_args( '--code=tub' ); 1 }, "fail check (code)" );
    like( $@, qr/Validation Failed for 'code=CODE': tub/, "fail check message (code)" );

    ok( !eval { parse_args( '-regex' => 'Whatever' ); 1 }, "fail check (regex)" );
    like( $@, qr/Validation Failed for 'regex=Regexp': Whatever/, "fail check message (regex)" );

    ok( !eval { parse_args( '--number' => 'a,b,1,2'); 1 }, "fail check (number)" );
    like( $@, qr/Validation Failed for 'number=number': a, b/, "fail check message (number)" );

    ok( !eval { parse_args( '-file' => '/Some/Fake/File' ); 1 }, "fail check (file)" );
    like( $@, qr{Validation Failed for 'file=file': /Some/Fake/File}, "fail check message (file)" );

    ok( !eval { parse_args( '-dir' => '/Some/Fake/Dir,/Another/Fake/Dir,.,..' ); 1 }, "fail check (dir)" );
    like( $@, qr{Validation Failed for 'dir=dir': /Some/Fake/Dir, /Another/Fake/Dir}, "fail check message (dir)" );
};

tests transform => sub {
    arg add5 => ( transform => sub { $_[0] + 5 }, check => 'number' );
    arg add6 => ( transform => sub { $_[0] + 6 }, check => 'number', list => 1 );

    my ( $params, $flags ) = parse_args(
        '-add5' => '5',
        '-add6' => '1,2,3',
        '--',
        '-tub',
        'blug'
    );

    is_deeply( $params, ['-tub', 'blug'], "Got params" );
    is_deeply(
        $flags,
        {
            add5 => 10,
            add6 => [ 7, 8 ,9 ],
        },
        "got flags"
    );
};

1;

