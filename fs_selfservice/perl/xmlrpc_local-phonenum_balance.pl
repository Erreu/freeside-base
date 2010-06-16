#!/usr/bin/perl

use strict;
use Frontier::Client;
use Data::Dumper;

my $phonenum = shift @ARGV;

my $server = new Frontier::Client (
        url => 'http://localhost:8080/selfservice/xmlrpc.cgi',
);

my $result = $server->call('FS.ClientAPI_XMLRPC.phonenum_balance',
  'phonenum' => $server->string($phonenum), # '3615588197',
);

#print Dumper($result);
die $result->{'error'} if $result->{'error'};

warn Dumper($result);

1;
