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
 


package RT::Condition::QueueChange;
require RT::Condition::Generic;

use strict;
use vars qw/@ISA/;
@ISA = qw(RT::Condition::Generic);


=head2 IsApplicable

If the queue has changed.

=cut

sub IsApplicable {
    my $self = shift;
    if ($self->TransactionObj->Field eq 'Queue') {
	    return(1);
    } 
    else {
	    return(undef);
    }
}

eval "require RT::Condition::QueueChange_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Condition/QueueChange_Vendor.pm});
eval "require RT::Condition::QueueChange_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Condition/QueueChange_Local.pm});

1;

