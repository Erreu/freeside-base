# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
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
# END BPS TAGGED BLOCK }}}
package RT::ObjectCustomFields;

use strict;
no warnings qw(redefine);

sub LimitToCustomField {
    my $self = shift;
    my $id = shift;
    $self->Limit( FIELD => 'CustomField', VALUE => $id );
}

sub LimitToObjectId {
    my $self = shift;
    my $id = shift || 0;
    $self->Limit( FIELD => 'ObjectId', VALUE => $id );
}

sub LimitToLookupType {
    my $self = shift;
    my $lookup = shift;
    unless ($self->{'_cfs_alias'}) {
        $self->{'_cfs_alias'}  = $self->NewAlias('CustomFields');
    }
    $self->Join( ALIAS1 => 'main',
                FIELD1 => 'CustomField',
                ALIAS2 => $self->{'_cfs_alias'},
                FIELD2 => 'id' );
    $self->Limit( ALIAS           => $self->{'_cfs_alias'},
                 FIELD           => 'LookupType',
                 OPERATOR        => '=',
                 VALUE           => $lookup );
}

sub HasEntryForCustomField {
    my $self = shift;
    my $id = shift;

    my @items = grep {$_->CustomField == $id } @{$self->ItemsArrayRef};

    if ($#items > 1) {
	die "$self HasEntry had a list with more than one of $id in it. this can never happen";
    }
    if ($#items == -1 ) {
	return undef;
    }
    else {
	return ($items[0]);
    }  
}

sub CustomFields {
    my $self = shift;
    my %seen;
    map { $_->CustomFieldObj } @{$self->ItemsArrayRef};
}

sub _DoSearch {
    my $self = shift;
    if ($self->{'_cfs_alias'}) {
    $self->Limit( ALIAS           => $self->{'_cfs_alias'},
                 FIELD           => 'Disabled',
                 OPERATOR        => '!=',
                 VALUE           =>  1);
    }
    $self->SUPER::_DoSearch()
}

1;
