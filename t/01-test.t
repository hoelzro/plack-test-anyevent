use strict;
use warnings;

use HTTP::Request::Common;
use Test::More tests => 36;
use Test::More;
use Plack::Test;

my $simple_app = sub {
    my ( $env ) = @_;

    return [
        200,
        ['Content-Type' => 'text/plain'],
        ['OK'],
    ];
};

my $delayed_app = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 1,
            cb    => sub {
                undef $timer;
                $respond->([
                    200,
                    ['Content-Type' => 'text/plain'],
                    ['OK'],
                ]);
            },
        );
    };
};

my $streaming_app = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $writer = $respond->([
            200,
            ['Content-Type' => 'text/plain'],
        ]);
        my $timer;
        my $i  = 0;

        $timer = AnyEvent->timer(
            interval => 1,
            cb       => sub {
                $writer->write($i++);
                if($i > 2) {
                    $writer->close;
                    undef $timer;
                }
            },
        );
    };
};

my $infinite_app = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $writer = $respond->([
            200,
            ['Content-Type' => 'text/plain'],
        ]);
        my $timer;
        my $i  = 0;
        $timer = AnyEvent->timer(
            interval => 1,
            cb       => sub {
                local $SIG{__WARN__} = sub {}; # $writer complains if its been
                                               # closed, and rightfully so.
                                               # We just don't want trouble
                                               # during testing.
                $writer->write($i++);
                ( undef ) = $timer; # keep a reference to $timer
            },
        );
    };
};

my @impls = qw(AnyEvent AE);

foreach $Plack::Test::Impl (@impls) {
    test_psgi $simple_app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        is $res->content_type, 'text/plain';
        is $res->content, 'OK';
    };

    test_psgi $delayed_app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        is $res->content_type, 'text/plain';
        is $res->content, 'OK';
    };

    test_psgi $streaming_app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        is $res->content_type, 'text/plain';
        is $res->content, '';

        my $i = 0;
        $res->on_content_received(sub {
            my ( $chunk ) = @_;
            is $chunk, $i++;
        });
        $res->recv;
    };

    test_psgi $infinite_app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        is $res->content_type, 'text/plain';
        is $res->content, '';

        my $i = 0;
        $res->on_content_received(sub {
            my ( $chunk ) = @_;
            is $chunk, $i++;
            if($i > 2) {
                $res->send;
            }
        });
        $res->recv;
    };
}
