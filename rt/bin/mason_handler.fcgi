#!/usr/bin/perl
# BEGIN LICENSE BLOCK
# 
# Copyright (c) 1996-2003 Jesse Vincent <jesse@bestpractical.com>
# 
# (Except where explictly superceded by other copyright notices)
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# Unless otherwise specified, all modifications, corrections or
# extensions to this work which alter its source code become the
# property of Best Practical Solutions, LLC when submitted for
# inclusion in the work.
# 
# 
# END LICENSE BLOCK

use strict;
use File::Basename;
require ('/opt/rt3/bin/webmux.pl');

my $h = &RT::Interface::Web::NewCGIHandler(@RT::MasonParameters);

# Enter CGI::Fast mode, which should also work as a vanilla CGI script.
require CGI::Fast;

RT::Init();

# Response loop
while ( my $cgi = CGI::Fast->new ) {
    # the whole point of fastcgi requires the env to get reset here..
    # So we must squash it again
    $ENV{'PATH'}   = '/bin:/usr/bin';
    $ENV{'CDPATH'} = '' if defined $ENV{'CDPATH'};
    $ENV{'SHELL'}  = '/bin/sh' if defined $ENV{'SHELL'};
    $ENV{'ENV'}    = '' if defined $ENV{'ENV'};
    $ENV{'IFS'}    = '' if defined $ENV{'IFS'};

    RT::ConnectToDatabase();

    if ( ( !$h->interp->comp_exists( $cgi->path_info ) )
        && ( $h->interp->comp_exists( $cgi->path_info . "/index.html" ) ) ) {
        $cgi->path_info( $cgi->path_info . "/index.html" );
    }

    eval { $h->handle_cgi_object($cgi); };
    if ($@) {
        $RT::Logger->crit($@);
    }


    if ($RT::Handle->TransactionDepth) {
        $RT::Handle->ForceRollback;
        $RT::Logger->crit("Transaction not committed. Usually indicates a software fault. Data loss may have occurred") ;
    }


}

1;
