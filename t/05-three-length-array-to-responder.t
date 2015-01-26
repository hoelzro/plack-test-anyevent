#!/usr/bin/env perl

use strict;
use Test::More tests => 5;

use Plack::Test;
$Plack::Test::Impl = 'AnyEvent';

use AnyEvent;
use HTTP::Request::Common;


my $app = sub {
  my ( $env ) = @_;

  sub{
    my $responder = shift;
    if($env->{QUERY_STRING} =~ /3-length/) {
      $responder->([200, ['Content-Type' => 'text/plain'], ['ok']]);
    } else {
      my $writer = $responder->([200, ['Content-Type' => 'text/plain']]);
      $writer->write('ok');
      $writer->close();
    }
  }
};

test_psgi $app, sub{
  my ( $cb ) = @_;

  my $num_callbacks_invoked = 0;

  my $res = $cb->(GET '/');
  $res->on_content_received(sub {
    $num_callbacks_invoked++;
    is $res->code, 200;
    is $res->content, 'ok';
  });
  $res->recv;

  my $res = $cb->(GET '/?3-length');
  $res->on_content_received(sub{
    $num_callbacks_invoked++;
    is $res->code, 200;
    is $res->content, 'ok';
  });
  $res->recv;

  is $num_callbacks_invoked, 2, 'make sure that both callbacks have been invoked';
};

done_testing;
