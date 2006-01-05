<%

  my $charged = <<END;
  sum( charged
       - coalesce(
           ( select sum(amount) from cust_bill_pay
             where cust_bill.invnum = cust_bill_pay.invnum )
           ,0
         )
       - coalesce(
           ( select sum(amount) from cust_credit_bill
             where cust_bill.invnum = cust_credit_bill.invnum )
           ,0
         )

     )
END

  my $owed_cols = <<END;
       coalesce(
         ( select $charged from cust_bill
           where cust_bill._date > extract(epoch from now())-2592000
             and cust_main.custnum = cust_bill.custnum
         )
         ,0
       ) as owed_0_30,

       coalesce(
         ( select $charged from cust_bill
           where cust_bill._date >  extract(epoch from now())-5184000
             and cust_bill._date <= extract(epoch from now())-2592000
             and cust_main.custnum = cust_bill.custnum
         )
         ,0
       ) as owed_30_60,

       coalesce(
         ( select $charged from cust_bill
           where cust_bill._date >  extract(epoch from now())-7776000
             and cust_bill._date <= extract(epoch from now())-5184000
             and cust_main.custnum = cust_bill.custnum
         )
         ,0
       ) as owed_60_90,

       coalesce(
         ( select $charged from cust_bill
           where cust_bill._date <= extract(epoch from now())-7776000
             and cust_main.custnum = cust_bill.custnum
         )
         ,0
       ) as owed_90_pl,

       coalesce(
         ( select $charged from cust_bill
           where cust_main.custnum = cust_bill.custnum
         )
         ,0
       ) as owed_total
END

  my $recurring = <<END;
        '0' != ( select freq from part_pkg
                   where cust_pkg.pkgpart = part_pkg.pkgpart )
END

  my $packages_cols = <<END;

       ( select count(*) from cust_pkg
           where cust_main.custnum = cust_pkg.custnum
             and $recurring
             and ( cancel = 0 or cancel is null )
       ) as uncancelled_pkgs,

       ( select count(*) from cust_pkg
           where cust_main.custnum = cust_pkg.custnum
             and $recurring
             and ( cancel = 0 or cancel is null )
             and ( susp = 0 or susp is null )
       ) as active_pkgs

END

  my $where = <<END;
where 0 <
  coalesce(
           ( select $charged from cust_bill
             where cust_main.custnum = cust_bill.custnum
           )
           ,0
         )
END

  my $agentnum = '';
  if ( $cgi->param('agentnum') =~ /^(\d+)$/ ) {
    $agentnum = $1;
    $where .= " AND agentnum = '$agentnum' ";
  }

  my $count_sql = "select count(*) from cust_main $where";

  my $sql_query = {
    'table'     => 'cust_main',
    'hashref'   => {},
    'select'    => "*, $owed_cols, $packages_cols",
    'extra_sql' => "$where order by coalesce(lower(company), ''), lower(last)",
  };

  if ( $agentnum ) {
    $owed_cols =~
      s/cust_bill\.custnum/cust_bill.custnum AND cust_main.agentnum = '$agentnum'/g;
  }
  my $total_sql = "select $owed_cols";
  my $total_sth = dbh->prepare($total_sql) or die dbh->errstr;
  $total_sth->execute or die $total_sth->errstr;
  my $row = $total_sth->fetchrow_hashref();

  my $conf = new FS::Conf;
  my $money_char = $conf->config('money_char') || '$';

%><%= include( 'elements/search.html',
                 'title'       => 'Accounts Receivable Aging Summary',
                 'name'        => 'customers',
                 'query'       => $sql_query,
                 'count_query' => $count_sql,
                 'header'      => [
                                    '#',
                                    'Customer',
                                    'Status', # (me)',
                                    #'Status', # (cust_main)',
                                    '0-30',
                                    '30-60',
                                    '60-90',
                                    '90+',
                                    'Total',
                                  ],
                 'footer'      => [
                                    '',
                                    'Total',
                                    '',
                                    #'',
                                    sprintf( $money_char.'%.2f',
                                             $row->{'owed_0_30'} ),
                                    sprintf( $money_char.'%.2f',
                                             $row->{'owed_30_60'} ),
                                    sprintf( $money_char.'%.2f',
                                             $row->{'owed_60_90'} ),
                                    sprintf( $money_char.'%.2f',
                                             $row->{'owed_90_pl'} ),
                                    sprintf( '<b>'. $money_char.'%.2f'. '</b>',
                                             $row->{'owed_total'} ),
                                  ],
                 'fields'      => [
                                    'custnum',
                                    'name',
                                    sub {
                                          my $row = shift;
                                          my $status = 'Cancelled';
                                          my $statuscol = 'FF0000';
                                          if ( $row->uncancelled_pkgs ) {
                                            $status = 'Suspended';
                                            $statuscol = 'FF9900';
                                            if ( $row->active_pkgs ) {
                                              $status = 'Active';
                                              $statuscol = '00CC00';
                                            }
                                          }
                                          $status;
                                        },
                                    #sub { ucfirst(shift->status) },
                                    sub { sprintf( $money_char.'%.2f',
                                                   shift->get('owed_0_30') ) },
                                    sub { sprintf( $money_char.'%.2f',
                                                   shift->get('owed_30_60') ) },
                                    sub { sprintf( $money_char.'%.2f',
                                                   shift->get('owed_60_90') ) },
                                    sub { sprintf( $money_char.'%.2f',
                                                   shift->get('owed_90_pl') ) },
                                    sub { sprintf( $money_char.'%.2f',
                                                   shift->get('owed_total') ) },
                                  ],
                 'links'       => [
                                    [ "${p}view/cust_main.cgi?", 'custnum' ],
                                    [ "${p}view/cust_main.cgi?", 'custnum' ],
                                    '',
                                    #'',
                                    '',
                                    '',
                                    '',
                                    '',
                                    '',
                                  ],
                 #'align'       => 'rlccrrrrr',
                 'align'       => 'rlcrrrrr',
                 #'size'        => [ '', '', '-1', '-1', '', '', '', '',  '', ],
                 #'style'       => [ '', '',  'b',  'b', '', '', '', '', 'b', ],
                 'size'        => [ '', '', '-1', '', '', '', '',  '', ],
                 'style'       => [ '', '',  'b', '', '', '', '', 'b', ],
                 'color'       => [
                                    '',
                                    '',
                                    sub {  
                                          my $row = shift;
                                          my $status = 'Cancelled';
                                          my $statuscol = 'FF0000';
                                          if ( $row->uncancelled_pkgs ) {
                                            $status = 'Suspended';
                                            $statuscol = 'FF9900';
                                            if ( $row->active_pkgs ) {
                                              $status = 'Active';
                                              $statuscol = '00CC00';
                                            }
                                          }
                                           $statuscol;
                                        },
                                    #sub { shift->statuscolor; },
                                    '',
                                    '',
                                    '',
                                    '',
                                    '',
                                  ],

             )
%>
