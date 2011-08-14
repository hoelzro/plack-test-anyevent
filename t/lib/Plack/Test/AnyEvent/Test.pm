package Plack::Test::AnyEvent::Test;

use strict;
use warnings;
use parent 'Test::Class';

use HTTP::Request::Common;
use Test::More;
use Plack::Test;

sub startup :Test(startup) {
    my ( $self ) = @_;

    $Plack::Test::Impl = $self->impl_name;
}

sub test_simple_app :Test(3) {
    my $app = sub {
        return [
            200,
            ['Content-Type' => 'text/plain'],
            ['OK'],
        ];
    };

    test_psgi $app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        is $res->content_type, 'text/plain';
        is $res->content, 'OK';
    };
}

sub test_delayed_app :Test(3) {
    my $app = sub {
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

    test_psgi $app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        is $res->content_type, 'text/plain';
        is $res->content, 'OK';
    };

}

sub test_streaming_app :Test(6) {
    my $app = sub {
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

    test_psgi $app, sub {
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
}

sub test_infinite_app :Test(6) {
    my $app = sub {
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
                    local $SIG{__WARN__} = sub {}; # $writer complains if its
                                                   # been closed, and
                                                   # rightfully so.  We just
                                                   # don't want trouble during
                                                   # testing.
                    $writer->write($i++);
                    ( undef ) = $timer; # keep a reference to $timer
                },
            );
        };
    };

    test_psgi $app, sub {
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

1;
