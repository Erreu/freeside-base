package FS::part_pkg::sql_generic;

use strict;
use vars qw(@ISA %info);
use DBI;
#use FS::Record qw(qsearch qsearchs);
use FS::part_pkg;

@ISA = qw(FS::part_pkg);

%info = (
    'name' => 'Base charge plus a per-domain metered rate from a configurable SQL query',
    'fields' => {
      'setup_fee' => { 'name' => 'Setup fee for this package',
                       'default' => 0,
                     },
      'recur_flat' => { 'name' => 'Base monthly charge for this package',
                        'default' => 0,
                      },
      'recur_included' => { 'name' => 'Units included',
                            'default' => 0,
                          },
      'recur_unit_charge' => { 'name' => 'Additional charge per unit',
                               'default' => 0,
                             },
      'datasrc' => { 'name' => 'DBI data source',
                     'default' => '',
                   },
      'db_username' => { 'name' => 'Database username',
                         'default' => '',
                       },
      'db_password' => { 'name' => 'Database username',
                         'default' => '',
                       },
      'query' => { 'name' => 'SQL query',
                   'default' => '',
                 },
    },
    'fieldorder' => [qw( setup_fee recur_flat recur_included recur_unit_charge datasrc db_username db_password query )],
   # 'setup' => 'what.setup_fee.value',
   # 'recur' => '\'my $dbh = DBI->connect(\"\' + what.datasrc.value + \'\", \"\' + what.db_username.value + \'\") or die $DBI::errstr; \'',
   #'recur' => '\'my $dbh = DBI->connect(\"\' + what.datasrc.value + \'\", \"\' + what.db_username.value + \'\", \"\' + what.db_password.value + \'\" ) or die $DBI::errstr; my $sth = $dbh->prepare(\"\' + what.query.value + \'\") or die $dbh->errstr; my $units = 0; foreach my $cust_svc ( grep { $_->part_svc->svcdb eq \"svc_domain\" } $cust_pkg->cust_svc ) { my $domain = $cust_svc->svc_x->domain; $sth->execute($domain) or die $sth->errstr; $units += $sth->fetchrow_arrayref->[0]; } $units -= \' + what.recur_included.value + \'; $units = 0 if $units < 0; \' + what.recur_flat.value + \' + $units * \' + what.recur_unit_charge.value + \';\'',
    #'recur' => '\'my $dbh = DBI->connect("\' + what.datasrc.value + \'", "\' + what.db_username.value + \'", "\' what.db_password.value + \'" ) or die $DBI::errstr; my $sth = $dbh->prepare("\' + what.query.value + \'") or die $dbh->errstr; my $units = 0; foreach my $cust_svc ( grep { $_->part_svc->svcdb eq "svc_domain" } $cust_pkg->cust_svc ) { my $domain = $cust_svc->svc_x->domain; $sth->execute($domain) or die $sth->errstr; $units += $sth->fetchrow_arrayref->[0]; } $units -= \' + what.recur_included.value + \'; $units = 0 if $units < 0; \' + what.recur_flat.value + \' + $units * \' + what.recur_unit_charge + \';\'',
    'weight' => '70',
);

sub calc_setup {
  my($self, $cust_pkg ) = @_;
  $self->option('setup_fee');
}

sub calc_recur {
  my($self, $cust_pkg ) = @_;

  my $dbh = DBI->connect( map { $self->option($_) }
                              qw( datasrc db_username db_password )
                        )
    or die $DBI::errstr;

  my $sth = $dbh->prepare( $self->option('query') )
    or die $dbh->errstr;

  my $units = 0;
  foreach my $cust_svc (
    grep { $_->part_svc->svcdb eq "svc_domain" } $cust_pkg->cust_svc
  ) {
    my $domain = $cust_svc->svc_x->domain;
    $sth->execute($domain) or die $sth->errstr;

    $units += $sth->fetchrow_arrayref->[0];
  }

  $units -= $self->option('recur_included');
  $units = 0 if $units < 0;

  $self->option('recur_flat') + $units * $self->option('recur_unit_charge');
}

1;
