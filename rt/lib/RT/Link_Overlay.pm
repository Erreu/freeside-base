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
=head1 NAME

  RT::Link - an RT Link object

=head1 SYNOPSIS

  use RT::Link;

=head1 DESCRIPTION

This module should never be called directly by client code. it's an internal module which
should only be accessed through exported APIs in Ticket other similar objects.

=head1 METHODS


=begin testing


use RT::Link;
my $link = RT::Link->new($RT::SystemUser);


ok (ref $link);
ok (UNIVERSAL::isa($link, 'RT::Link'));
ok (UNIVERSAL::isa($link, 'RT::Base'));
ok (UNIVERSAL::isa($link, 'RT::Record'));
ok (UNIVERSAL::isa($link, 'DBIx::SearchBuilder::Record'));

=end testing

=cut

use strict;
no warnings qw(redefine);


use Carp;
use RT::URI;


# {{{ sub Create 

=head2 Create PARAMHASH

Create a new link object. Takes 'Base', 'Target' and 'Type'.
Returns undef on failure or a Link Id on success.

=cut

sub Create {
    my $self = shift;
    my %args = ( Base   => undef,
                 Target => undef,
                 Type   => undef,
                 @_ );

    my $base = RT::URI->new( $self->CurrentUser );
    $base->FromURI( $args{'Base'} );

    unless ( $base->Scheme ) {
        $RT::Logger->warning( "$self couldn't resolve base:'"
                              . $args{'Base'} . " - "
                              . $base->Scheme
                              . "' into a URI\n" );

        #use Data::Dumper;
        #$RT::Logger->warning(scalar Dumper $base);
        return (undef);
    }

    my $target = RT::URI->new( $self->CurrentUser );
    $target->FromURI( $args{'Target'} );

    unless ( $target->Resolver ) {
        $RT::Logger->warning( "$self couldn't resolve target:'"
                              . $args{'Target'} . " - "
                              . "' into a URI\n" );

        #use Data::Dumper;
        #$RT::Logger->warning(scalar Dumper $target);
        return (undef);
    }

    my $base_id   = 0;
    my $target_id = 0;




    if ( $base->IsLocal ) {
        unless (UNIVERSAL::can($base->Object, 'Id')) {
            return (undef, $self->loc("[_1] appears to be a local object, but can't be found in the database", $args{'Base'}));
        
        }
        $base_id = $base->Object->Id;
    }
    if ( $target->IsLocal ) {
        unless (UNIVERSAL::can($target->Object, 'Id')) {
            return (undef, $self->loc("[_1] appears to be a local object, but can't be found in the database", $args{'Target'}));
        
        }
        $target_id = $target->Object->Id;
    }

    # {{{ We don't want references to ourself
    if ( $base->URI eq $target->URI ) {
        return ( 0, $self->loc("Can't link a ticket to itself") );
    }

    # }}}

    my ( $id, $msg ) = $self->SUPER::Create( Base        => $base->URI,
                                             Target      => $target->URI,
                                             LocalBase   => $base_id,
                                             LocalTarget => $target_id,
                                             Type        => $args{'Type'} );
    return ( $id, $msg );
}

# }}}
 # {{{ sub LoadByParams

=head2 LoadByParams

  Load an RT::Link object from the database.  Takes three parameters
  
  Base => undef,
  Target => undef,
  Type =>undef
 
  Base and Target are expected to be integers which refer to Tickets or URIs
  Type is the link type

=cut

sub LoadByParams {
    my $self = shift;
    my %args = ( Base   => undef,
                 Target => undef,
                 Type   => undef,
                 @_ );

    my $base = RT::URI->new($self->CurrentUser);
    $base->FromURI( $args{'Base'} );

    my $target = RT::URI->new($self->CurrentUser);
    $target->FromURI( $args{'Target'} );
    
    unless ($base->Resolver && $target->Resolver) {
        return ( 0, $self->loc("Couldn't load link") );
    }


    my ( $id, $msg ) = $self->LoadByCols( Base   => $base->URI,
                                          Type   => $args{'Type'},
                                          Target => $target->URI );

    unless ($id) {
        return ( 0, $self->loc("Couldn't load link") );
    }
}

# }}}
# {{{ sub Load 

=head2 Load

  Load an RT::Link object from the database.  Takes one parameter, the id of an entry in the links table.


=cut

sub Load {
    my $self       = shift;
    my $identifier = shift;




    if ( $identifier !~ /^\d+$/ ) {
        return ( 0, $self->loc("That's not a numerical id") );
    }
    else {
        my ( $id, $msg ) = $self->LoadById($identifier);
        unless ( $self->Id ) {
            return ( 0, $self->loc("Couldn't load link") );
        }
        return ( $id, $msg );
    }
}

# }}}


# {{{ TargetURI

=head2 TargetURI

returns an RT::URI object for the "Target" of this link.

=cut

sub TargetURI {
    my $self = shift;
    my $URI = RT::URI->new($self->CurrentUser);
    $URI->FromURI($self->Target);
    return ($URI);
}

# }}}
# {{{ sub TargetObj 

=head2 TargetObj

=cut

sub TargetObj {
  my $self = shift;
   return $self->TargetURI->Object;
}
# }}}

# {{{ BaseURI

=head2 BaseURI

returns an RT::URI object for the "Base" of this link.

=cut

sub BaseURI {
    my $self = shift;
    my $URI = RT::URI->new($self->CurrentUser);
    $URI->FromURI($self->Base);
    return ($URI);
}

# }}}
# {{{ sub BaseObj

=head2 BaseObj

=cut

sub BaseObj {
  my $self = shift;
  return $self->BaseURI->Object;
}
# }}}



# Static methods:

# {{{ sub BaseIsLocal

=head2 BaseIsLocal

Returns true if the base of this link is a local ticket

=cut

sub BaseIsLocal {
  my $self = shift;
  $RT::Logger->crit("Link::BaseIsLocal is deprecated in favor of Link->BaseURI->IsLocal");
  return $self->BaseURI->IsLocal;
}

# }}}

# {{{ sub TargetIsLocal

=head2 TargetIsLocal

Returns true if the target of this link is a local ticket

=cut

sub TargetIsLocal {
  my $self = shift;
  $RT::Logger->crit("Link::BaseIsLocal is deprecated in favor of Link->BaseURI->IsLocal");
  return $self->TargetURI->IsLocal;
}

# }}}


# {{{ sub BaseAsHREF 

=head2 BaseAsHREF

Returns an HTTP url to access the base of this link

=cut

sub BaseAsHREF {
  my $self = shift;
  $RT::Logger->crit("Link::BaseAsHREF deprecated in favor of ->BaseURI->AsHREF");
  return $self->BaseURI->HREF;
}
# }}}

# {{{ sub TargetAsHREF 

=head2 TargetAsHREF

return an HTTP url to access the target of this link

=cut

sub TargetAsHREF {
  my $self = shift;
  $RT::Logger->crit("Link::TargetAsHREF deprecated in favor of ->TargetURI->AsHREF");
  return $self->TargetURI->HREF;
}
# }}}

# {{{ sub AsHREF - Converts Link URIs to HTTP URLs

=head2 URI

Takes a URI and returns an http: url to access that object.

=cut


sub AsHREF {
    my $self=shift;
   
    $RT::Logger->crit("AsHREF is gone. look at URI::HREF to figure out what to do with \$URI");
}

# }}}

1;
 
