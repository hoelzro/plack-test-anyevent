package Plack::Test::AnyEvent::Response;

use strict;
use warnings;
use parent 'HTTP::Response';

sub from_psgi {
    my $class = shift;

    my $self = HTTP::Response::from_psgi($class, @_);
    bless $self, $class;

    return $self;
}

sub send {
    my ( $self, @values ) = @_;

    return $self->{'_cond'}->send(@values);
}

sub recv {
    my ( $self ) = @_;

    $self->{'_cond'}->recv;
}

sub on_content_received {
    my ( $self, $cb ) = @_;

    if($cb) {
        $self->{'_on_content_received'} = $cb;
    }
    return $self->{'_on_content_received'};
}

## no critic (RequireUseStrict)
package Plack::Test::AnyEvent;

## use critic (RequireUseStrict)
use strict;
use warnings;
use autodie qw(pipe);

use AnyEvent::Handle;
use Carp;
use HTTP::Request;
use HTTP::Response;
use HTTP::Message::PSGI;
use IO::Handle;
use Try::Tiny;

# code adapted from Plack::Test::MockHTTP
sub test_psgi {
    my ( %args ) = @_;

    my $client = delete $args{client} or croak "client test code needed";
    my $app    = delete $args{app}    or croak "app needed";

    my $cb     = sub {
        my ( $req ) = @_;
        $req->uri->scheme('http')    unless defined $req->uri->scheme;
        $req->uri->host('localhost') unless defined $req->uri->host;
        my $env = $req->to_psgi;
        $env->{'psgi.streaming'}   = 1;
        $env->{'psgi.nonblocking'} = 1;

        my $res = try {
            $app->($env);
        } catch {
            HTTP::Response->from_psgi([ 500, [ 'Content-Type' => 'text/plain' ], [ $_ ] ]);
        };

        if(ref($res) eq 'CODE') {
            my ( $status, $headers, $body );
            my ( $read, $write );

            my $cond = AnyEvent->condvar;

            $res->(sub {
                my ( $ref ) = @_;
                ( $status, $headers, $body ) = @$ref;

                $cond->send;

                unless(defined $body) {
                    pipe $read, $write;
                    $write = IO::Handle->new_from_fd($write, 'w');
                    $write->autoflush(1);
                    return $write;
                }
            });

            unless(defined $status) {
                $cond->recv;
            }

            if(defined $body) {
                $res = HTTP::Response->from_psgi([ $status, $headers, $body ]);
            } else {
                push @$headers, 'Transfer-Encoding', 'chunked';
                $res = Plack::Test::AnyEvent::Response->from_psgi([ $status, $headers, [] ]);
                $res->on_content_received(sub {});
                my $h;
                $res->{'_cond'} = AnyEvent->condvar(cb => sub {
                    undef $h;
                    close $read;
                    close $write;
                });

                $h = AnyEvent::Handle->new(
                    fh      => $read,
                    on_read => sub {
                        my $buf = $h->rbuf;
                        $h->rbuf = '';
                        $res->content($res->content . $buf);
                        $res->on_content_received->($buf);
                    },
                    on_eof => sub {
                        $res->send;
                    },
                    ## handle errors
                );
            }
        } else {
            $res = HTTP::Response->from_psgi($res);
            $res->request($req);
        }

        return $res;
    };

    $client->($cb);
}

1;

__END__

# ABSTRACT:  A short description of Plack::Test::AnyEvent

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 SEE ALSO

=cut
