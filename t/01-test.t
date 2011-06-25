use strict;
use warnings;

use HTTP::Request::Common;
use Test::More tests => 60;
use Scalar::Util qw(weaken);
use Test::More;
use Test::Exception;
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

my $bad_app = sub {
    die "bad apple";
};

my $responsible_app = sub {
    eval {
        die "good apple";
    };
    return [
        200,
        ['Content-Type' => 'text/plain'],
        ['All Alright'],
    ];
};

my $bad_app_delayed = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 0.5,
            cb    => sub {
                undef $timer;
                die "bad apple";
            },
        );
    };
};

my $responsible_app_delayed = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 0.5,
            cb    => sub {
                undef $timer;
                eval {
                    die "bad apple";
                };
                $respond->([
                    200,
                    ['Content-Type' => 'text/plain'],
                    ['All Alright'],
                ]);
            },
        );
    };
};

my $bad_app_delayed2 = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 0.5,
            cb    => sub {
                undef $timer;
                $respond->([
                    200,
                    ['Content-Type' => 'text/plain'],
                    'Hey!',
                ]);
                die "bad apple";
            },
        );
    };
};

my $responsible_app_delayed2 = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 0.5,
            cb    => sub {
                undef $timer;
                $respond->([
                    200,
                    ['Content-Type' => 'text/plain'],
                    'Hey!',
                ]);
                eval {
                    die "bad apple";
                };
            },
        );
    };
};

my $bad_app_delayed3 = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        die "bad apple";
    };
};

my $responsible_app_delayed3 = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        eval {
            die "bad apple";
        };
        $respond->([
            200,
            ['Content-Type' => 'text/plain'],
            ['All Alright'],
        ]);
    };
};

my $bad_app_streaming = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 0.5,
            cb    => sub {
                my $writer = $respond->([
                    200,
                    ['Content-Type' => 'text/plain'],
                ]);

                $timer = AnyEvent->timer(
                    after => 0.5,
                    cb    => sub {
                        die "bad apple";
                    },
                );
            },
        );
    };
};

my $responsible_app_streaming = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $timer;
        $timer = AnyEvent->timer(
            after => 0.5,
            cb    => sub {
                my $writer = $respond->([
                    200,
                    ['Content-Type' => 'text/plain'],
                ]);

                $timer = AnyEvent->timer(
                    after => 0.5,
                    cb    => sub {
                        eval {
                            die "bad apple";
                        };
                        $writer->write('All Alright');
                        $writer->close;
                    },
                );
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

    test_psgi $bad_app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 500;
    };

    test_psgi $responsible_app, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
    };

    test_psgi $bad_app_delayed, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 500;
    };

    test_psgi $responsible_app_delayed, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
    };

    test_psgi $bad_app_delayed2, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
    };

    test_psgi $responsible_app_delayed2, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
    };

    test_psgi $bad_app_delayed3, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 500;
    };

    test_psgi $responsible_app_delayed3, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
    };

    test_psgi $bad_app_streaming, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        my $timer = AnyEvent->timer(
            after => 5,
            cb    => sub {
                $res->send; # self-inflicted timeout
            },
        );
        is $res->code, 200;
        $res->on_content_received(sub {
            # no-op
        });
        throws_ok {
            $res->recv;
        } qr/bad apple/;
    };

    test_psgi $responsible_app_streaming, sub {
        my ( $cb ) = @_;

        my $res = $cb->(GET '/');
        is $res->code, 200;
        $res->on_content_received(sub {
            # no-op
        });
        lives_ok {
            $res->recv;
        };
    };
}

done_testing;
