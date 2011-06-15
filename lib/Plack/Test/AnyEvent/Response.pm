package
    Plack::Test::AnyEvent::Response;

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

1;
