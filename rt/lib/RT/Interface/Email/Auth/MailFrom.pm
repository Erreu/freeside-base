# {{{ BEGIN BPS TAGGED BLOCK
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2004 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# }}} END BPS TAGGED BLOCK
package RT::Interface::Email::Auth::MailFrom;
use RT::Interface::Email qw(ParseSenderAddressFromHead CreateUser);

# This is what the ordinary, non-enhanced gateway does at the moment.

sub GetCurrentUser {
    my %args = ( Message     => undef,
                 CurrentUser => undef,
                 AuthLevel   => undef,
                 Ticket      => undef,
                 Queue       => undef,
                 Action      => undef,
                 @_ );


    # We don't need to do any external lookups
    my ( $Address, $Name ) = ParseSenderAddressFromHead( $args{'Message'}->head );
    my $CurrentUser = RT::CurrentUser->new();
    $CurrentUser->LoadByEmail($Address);

    unless ( $CurrentUser->Id ) {
        $CurrentUser->LoadByName($Address);
    }

    if ( $CurrentUser->Id ) {
        return ( $CurrentUser, 1 );
    }
    


    # If the user can't be loaded, we may need to create one. Figure out the acl situation.
    my $unpriv = RT::Group->new($RT::SystemUser);
    $unpriv->LoadSystemInternalGroup('Unprivileged');
    unless ( $unpriv->Id ) {
        $RT::Logger->crit( "Auth::MailFrom couldn't find the 'Unprivileged' internal group" );
        return ( $args{'CurrentUser'}, -1 );
    }

    my $everyone = RT::Group->new($RT::SystemUser);
    $everyone->LoadSystemInternalGroup('Everyone');
    unless ( $everyone->Id ) {
        $RT::Logger->crit( "Auth::MailFrom couldn't find the 'Everyone' internal group");
        return ( $args{'CurrentUser'}, -1 );
    }

    # but before we do that, we need to make sure that the created user would have the right
    # to do what we're doing.
    if ( $args{'Ticket'} && $args{'Ticket'}->Id ) {
        # We have a ticket. that means we're commenting or corresponding
        if ( $args{'Action'} =~ /^comment$/i ) {

            # check to see whether "Everyone" or "Unprivileged users" can comment on tickets
            unless ( $everyone->PrincipalObj->HasRight(
                                                      Object => $args{'Queue'},
                                                      Right => 'CommentOnTicket'
                     )
                     || $unpriv->PrincipalObj->HasRight(
                                                      Object => $args{'Queue'},
                                                      Right => 'CommentOnTicket'
                     )
              ) {
                return ( $args{'CurrentUser'}, 0 );
            }
        }
        elsif ( $args{'Action'} =~ /^correspond$/i ) {

            # check to see whether "Everybody" or "Unprivileged users" can correspond on tickets
            unless ( $everyone->PrincipalObj->HasRight(Object => $args{'Queue'},
                                                       Right  => 'ReplyToTicket'
                     )
                     || $unpriv->PrincipalObj->HasRight(
                                                       Object => $args{'Queue'},
                                                       Right  => 'ReplyToTicket'
                     )
              ) {
                return ( $args{'CurrentUser'}, 0 );
            }

        }
        else {
            return ( $args{'CurrentUser'}, 0 );
        }
    }

    # We're creating a ticket
    elsif ( $args{'Queue'} && $args{'Queue'}->Id ) {

        # check to see whether "Everybody" or "Unprivileged users" can create tickets in this queue
        unless ( $everyone->PrincipalObj->HasRight( Object => $args{'Queue'},
                                                    Right  => 'CreateTicket' )
          ) {
            return ( $args{'CurrentUser'}, 0 );
        }

    }

    $CurrentUser = CreateUser( undef, $Address, $Name, $Address, $args{'Message'} );

    return ( $CurrentUser, 1 );
}

eval "require RT::Interface::Email::Auth::MailFrom_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Interface/Email/Auth/MailFrom_Vendor.pm});
eval "require RT::Interface::Email::Auth::MailFrom_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Interface/Email/Auth/MailFrom_Local.pm});

1;
