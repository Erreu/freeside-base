package FS::ConfDefaults;

=head1 NAME

FS::ConfDefaults - Freeside configuration default and available values

=head1 SYNOPSIS

  use FS::ConfDefaults;

  @avail_cust_fields = FS::ConfDefaults->cust_fields_avail();

=head1 DESCRIPTION

Just a small class to keep config default and available values

=head1 METHODS

=over 4

=item cust_fields_avail

Returns a list, suitable for assigning to a hash, of available values and
labels for customer fields values.

=cut

# XXX should use msgcat for "Day phone" and "Night phone", but how?
sub cust_fields_avail { (

  'Cust. Status | Customer' =>
    'Status | Last, First or Company (Last, First)',
  'Cust# | Cust. Status | Customer' =>
    'custnum | Status | Last, First or Company (Last, First)',

  'Cust. Status | Name | Company' =>
    'Status | Last, First | Company',
  'Cust# | Cust. Status | Name | Company' =>
    'custnum | Status | Last, First | Company',

  'Cust. Status | (bill) Customer | (service) Customer' =>
    'Status | Last, First or Company (Last, First) | (same for service contact if present)',
  'Cust# | Cust. Status | (bill) Customer | (service) Customer' =>
    'custnum | Status | Last, First or Company (Last, First) | (same for service contact if present)',

  'Cust. Status | (bill) Name | (bill) Company | (service) Name | (service) Company' =>
    'Status | Last, First | Company | (same for service address if present)',
  'Cust# | Cust. Status | (bill) Name | (bill) Company | (service) Name | (service) Company' =>
    'custnum | Status | Last, First | Company | (same for service address if present)',

  'Cust# | Cust. Status | Name | Company | Address 1 | Address 2 | City | State | Zip | Country | Day phone | Night phone | Invoicing email(s)' => 
    'custnum | Status | Last, First | Company | (all address fields ) | Day phone | Night phone | Invoicing email(s)',

  'Cust# | Cust. Status | Name | Company | Address 1 | Address 2 | City | State | Zip | Country | Day phone | Night phone | Fax number | Invoicing email(s) | Payment Type' => 
    'custnum | Status | Last, First | Company | (all address fields ) | ( all phones ) | Invoicing email(s) | Payment Type',

); }

=back

=head1 BUGS

Not yet.

=head1 SEE ALSO

L<FS::Conf>

=cut

1;
