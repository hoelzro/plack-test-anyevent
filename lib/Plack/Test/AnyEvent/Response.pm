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

    $self->{'_cond'}->send(@values);
}

sub recv {
    my ( $self ) = @_;

    my $cond = $self->{'_cond'};

    local $SIG{__DIE__} = sub {
        my $i = 0;

        my @last_eval_frame;

        while(my @info = caller($i)) {
            my ( $subroutine, $evaltext ) = @info[3, 6];

            if($subroutine eq '(eval)' && !defined($evaltext)) {
                @last_eval_frame = caller($i + 1);
                last;
            }
        } continue {
            $i++;
        }

        if(@last_eval_frame) {
            my ( $subroutine ) = $last_eval_frame[3];

            ## does this always work?
            if($subroutine =~ /^AnyEvent::Impl/) {
                $cond->send($_[0]);
            }
        }
    };

    my $ex = $cond->recv;
    if($ex) {
        die $ex;
    }
}

sub on_content_received {
    my ( $self, $cb ) = @_;

    if($cb) {
        $self->{'_on_content_received'} = $cb;
    }
    return $self->{'_on_content_received'};
}

1;

=pod

=begin comment

=over

=item from_psgi

=item send

=item recv

=item on_content_received

=back

=end comment

=cut
