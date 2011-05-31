#!/usr/bin/perl

package RT::Ticket;
use strict;

=head2 MissingRequiredFields

Return all custom fields with the Required flag set for which this object
doesn't have any non-empty values.

=cut

sub MissingRequiredFields {
    my $self = shift;
    my $CustomFields = $self->CustomFields;
    my @results;
    while ( my $CF = $CustomFields->Next ) {
        next if !$CF->Required;
        if ( !length($self->FirstCustomFieldValue($CF->Id) || '') )  {
            push @results, $CF;
        }
    }
    return @results;
}

1;
