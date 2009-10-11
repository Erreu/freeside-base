<% include( 'elements/search.html',
                 'title'       => 'Line items',
                 'name'        => 'line items',
                 'query'       => $query,
                 'count_query' => $count_query,
                 'count_addl'  => [ $money_char. '%.2f total', ],
                 'header'      => [
                   '#',
                   'Description',
                   'Setup charge',
                   ( $use_usage eq 'usage'
                     ? 'Usage charge'
                     : 'Recurring charge'
                   ),
                   'Invoice',
                   'Date',
                   FS::UI::Web::cust_header(),
                 ],
                 'fields'      => [
                   'billpkgnum',
                   sub { $_[0]->pkgnum > 0
                           ? $_[0]->get('pkg')      # possibly use override.pkg
                           : $_[0]->get('itemdesc') # but i think this correct
                       },
                   #strikethrough or "N/A ($amount)" or something these when
                   # they're not applicable to pkg_tax search
                   sub { sprintf($money_char.'%.2f', shift->setup ) },
                   sub { my $row = shift;
                         my $value = 0;
                         if ( $use_usage eq 'recurring' ) {
                           $value = $row->recur - $row->usage;
                         } elsif ( $use_usage eq 'usage' ) {
                           $value = $row->usage;
                         } else {
                           $value = $row->recur;
                         }
                         sprintf($money_char.'%.2f', $value );
                       },
                   'invnum',
                   sub { time2str('%b %d %Y', shift->_date ) },
                   \&FS::UI::Web::cust_fields,
                 ],
                 'links'       => [
                   '',
                   '',
                   '',
                   '',
                   $ilink,
                   $ilink,
                   ( map { $_ ne 'Cust. Status' ? $clink : '' }
                         FS::UI::Web::cust_header()
                   ),
                 ],
                 'align' => 'rlrrrc'.FS::UI::Web::cust_aligns(),
                 'color' => [ 
                              '',
                              '',
                              '',
                              '',
                              '',
                              '',
                              FS::UI::Web::cust_colors(),
                            ],
                 'style' => [ 
                              '',
                              '',
                              '',
                              '',
                              '',
                              '',
                              FS::UI::Web::cust_styles(),
                            ],
           )
%>
<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Financial reports');

my $conf = new FS::Conf;

#here is the agent virtualization
my $agentnums_sql =
  $FS::CurrentUser::CurrentUser->agentnums_sql( 'table' => 'cust_main' );

my @where = ( $agentnums_sql );

my($beginning, $ending) = FS::UI::Web::parse_beginning_ending($cgi);
push @where, "_date >= $beginning",
             "_date <= $ending";

push @where , " payby != 'COMP' "
  unless $cgi->param('include_comp_cust');

if ( $cgi->param('agentnum') =~ /^(\d+)$/ ) {
  push @where, "cust_main.agentnum = $1";
}

#classnum
# not specified: all classes
# 0: empty class
# N: classnum
my $use_override = $cgi->param('use_override');
if ( $cgi->param('classnum') =~ /^(\d+)$/ ) {
  my $comparison = '';
  if ( $1 == 0 ) {
    $comparison = "IS NULL";
  } else {
    $comparison = "= $1";
  }

  if ( $use_override ) {
    push @where, "(
      part_pkg.classnum $comparison AND pkgpart_override IS NULL OR
      override.classnum $comparison AND pkgpart_override IS NOT NULL
    )";
  } else {
    push @where, "part_pkg.classnum $comparison";
  }
}

if ( $cgi->param('taxclass')
     && ! $cgi->param('istax')  #no part_pkg.taxclass in this case
                                #(should we save a taxclass or a link to taxnum
                                # in cust_bill_pkg or something like
                                # cust_bill_pkg_tax_location?)
   )
{

  #override taxclass when use_override is specified?  probably
  #if ( $use_override ) {
  #
  #  push @where,
  #    ' ( '. join(' OR ',
  #                  map {
  #                        ' (    part_pkg.taxclass = '. dbh->quote($_).
  #                        '      AND pkgpart_override IS NULL '.
  #                        '   OR '.
  #                        '      override.taxclass = '. dbh->quote($_).
  #                        '      AND pkgpart_override IS NOT NULL '.
  #                        ' ) '
  #                      }
  #                      $cgi->param('taxclass')
  #               ).
  #    ' ) ';
  #
  #} else {

    push @where,
      ' ( '. join(' OR ',
                    map ' part_pkg.taxclass = '.dbh->quote($_),
                        $cgi->param('taxclass')
                 ).
      ' ) ';

  #}

}

if ( $cgi->param('out') ) {

  my ( $loc_sql, @param ) = FS::cust_pkg->location_sql( 'ornull' => 1 );
  while ( $loc_sql =~ /\?/ ) { #easier to do our own substitution
    $loc_sql =~ s/\?/'cust_main_county.'.shift(@param)/e;
  }

  $loc_sql =~ s/cust_pkg\.locationnum/cust_bill_pkg_tax_location.locationnum/g
    if $cgi->param('istax');

  push @where, "
    0 = (
          SELECT COUNT(*) FROM cust_main_county
           WHERE cust_main_county.tax > 0
             AND $loc_sql
        )
  ";

  #not linked to by anything, but useful for debugging "out of taxable region"
  if ( grep $cgi->param($_), qw( county state country ) ) {

    my %ph = map { $_ => dbh->quote( $cgi->param($_) ) }
                 qw( county state country );

    my ( $loc_sql, @param ) = FS::cust_pkg->location_sql;
    while ( $loc_sql =~ /\?/ ) { #easier to do our own substitution
      $loc_sql =~ s/\?/$ph{shift(@param)}/e;
    }

    push @where, $loc_sql;

  }

} elsif ( $cgi->param('country') ) {

  my @counties = $cgi->param('county');
   
  if ( scalar(@counties) > 1 ) {

    #hacky, could be more efficient.  care if it is ever used for more than the
    # tax-report_groups filtering kludge

    my $locs_sql =
      ' ( '. join(' OR ', map {

          my %ph = ( 'county' => dbh->quote($_),
                     map { $_ => dbh->quote( $cgi->param($_) ) }
                       qw( state country )
                   );

          my ( $loc_sql, @param ) = FS::cust_pkg->location_sql;
          while ( $loc_sql =~ /\?/ ) { #easier to do our own substitution
            $loc_sql =~ s/\?/$ph{shift(@param)}/e;
          }

          $loc_sql;

        } @counties

      ). ' ) ';

    push @where, $locs_sql;

  } else {

    my %ph = map { $_ => dbh->quote( $cgi->param($_) ) }
                 qw( county state country );

    my ( $loc_sql, @param ) = FS::cust_pkg->location_sql;
    while ( $loc_sql =~ /\?/ ) { #easier to do our own substitution
      $loc_sql =~ s/\?/$ph{shift(@param)}/e;
    }

    push @where, $loc_sql;

  }
   
  if ( $cgi->param('istax') ) {
    if ( $cgi->param('taxname') ) {
      push @where, 'itemdesc = '. dbh->quote( $cgi->param('taxname') );
    #} elsif ( $cgi->param('taxnameNULL') {
    } else {
      push @where, "( itemdesc IS NULL OR itemdesc = '' OR itemdesc = 'Tax' )";
    }
  } elsif ( $cgi->param('nottax') ) {
    #what can we usefully do with "taxname" ????  look up a class???
  } else {
    #warn "neither nottax nor istax parameters specified";
  }

  if ( $cgi->param('taxclassNULL') ) {

    my %hash = ( 'country' => scalar($cgi->param('country')) );
    foreach (qw( state county )) {
      $hash{$_} = scalar($cgi->param($_)) if $cgi->param($_);
    }
    my $cust_main_county = qsearchs('cust_main_county', \%hash);
    die "unknown base region for empty taxclass" unless $cust_main_county;

    my $same_sql = $cust_main_county->sql_taxclass_sameregion;
    push @where, $same_sql if $same_sql;

  }

} elsif ( scalar( grep( /locationtaxid/, $cgi->param ) ) ) {

  # this should really be shoved out to FS::cust_pkg->location_sql or something
  # along with the code in report_newtax.cgi

  my %pn = (
   'county'        => 'tax_rate_location.county',
   'state'         => 'tax_rate_location.state',
   'city'          => 'tax_rate_location.city',
   'locationtaxid' => 'cust_bill_pkg_tax_rate_location.locationtaxid',
  );

  my %ph = map { ( $pn{$_} => dbh->quote( $cgi->param($_) || '' ) ) }
           qw( county state city locationtaxid );

  push @where,
    join( ' AND ', map { "( $_ = $ph{$_} OR $ph{$_} = '' AND $_ IS NULL)" }
                   keys %ph
    );

}

if ( $cgi->param('itemdesc') ) {
  if ( $cgi->param('itemdesc') eq 'Tax' ) {
    push @where, "(itemdesc='Tax' OR itemdesc is null)";
  } else {
    push @where, 'itemdesc='. dbh->quote($cgi->param('itemdesc'));
  }
}

if ( $cgi->param('report_group') =~ /^(=|!=) (.*)$/ && $cgi->param('istax') ) {
  my ( $group_op, $group_value ) = ( $1, $2 );
  if ( $group_op eq '=' ) {
    #push @where, 'itemdesc LIKE '. dbh->quote($group_value.'%');
    push @where, 'itemdesc = '. dbh->quote($group_value);
  } elsif ( $group_op eq '!=' ) {
    push @where, '( itemdesc != '. dbh->quote($group_value) .' OR itemdesc IS NULL )';
  } else {
    die "guru meditation #00de: group_op $group_op\n";
  }
  
}

push @where, 'cust_bill_pkg.pkgnum != 0' if $cgi->param('nottax');
push @where, 'cust_bill_pkg.pkgnum  = 0' if $cgi->param('istax');

if ( $cgi->param('cust_tax') ) {
  #false laziness -ish w/report_tax.cgi
  my $cust_exempt;
  if ( $cgi->param('taxname') ) {
    my $q_taxname = dbh->quote($cgi->param('taxname'));
    $cust_exempt =
      "( tax = 'Y'
         OR EXISTS ( SELECT 1 FROM cust_main_exemption
                       WHERE cust_main_exemption.custnum = cust_main.custnum
                         AND cust_main_exemption.taxname = $q_taxname )
       )
      ";
  } else {
    $cust_exempt = " tax = 'Y' ";
  }

  push @where, $cust_exempt;
}

my $use_usage = $cgi->param('use_usage');

my $count_query;
if ( $cgi->param('pkg_tax') ) {

  $count_query =
    "SELECT COUNT(*),
            SUM(
                 ( CASE WHEN part_pkg.setuptax = 'Y'
                        THEN cust_bill_pkg.setup
                        ELSE 0
                   END
                 )
                 +
                 ( CASE WHEN part_pkg.recurtax = 'Y'
                        THEN cust_bill_pkg.recur
                        ELSE 0
                   END
                 )
               )
    ";

  push @where, "(    ( part_pkg.setuptax = 'Y' AND cust_bill_pkg.setup > 0 )
                  OR ( part_pkg.recurtax = 'Y' AND cust_bill_pkg.recur > 0 ) )",
               "( tax != 'Y' OR tax IS NULL )";

} elsif ( $cgi->param('taxable') ) {

  my $setup_taxable = "(
    CASE WHEN part_pkg.setuptax = 'Y'
         THEN 0
         ELSE cust_bill_pkg.setup
    END
  )";

  my $recur_taxable = "(
    CASE WHEN part_pkg.recurtax = 'Y'
         THEN 0
         ELSE cust_bill_pkg.recur
    END
  )";

  my $exempt = "(
    SELECT COALESCE( SUM(amount), 0 ) FROM cust_tax_exempt_pkg
      WHERE cust_tax_exempt_pkg.billpkgnum = cust_bill_pkg.billpkgnum
  )";

  $count_query =
    "SELECT COUNT(*), SUM( $setup_taxable + $recur_taxable - $exempt )";

  push @where,
    #not tax-exempt package (setup or recur)
    "(
          ( ( part_pkg.setuptax != 'Y' OR part_pkg.setuptax IS NULL )
            AND cust_bill_pkg.setup > 0 )
       OR
          ( ( part_pkg.recurtax != 'Y' OR part_pkg.recurtax IS NULL )
            AND cust_bill_pkg.recur > 0 )
    )",
    #not a tax_exempt customer
    "( tax != 'Y' OR tax IS NULL )";
    #not covered in full by a monthly tax exemption (texas tax)
    "0 < ( $setup_taxable + $recur_taxable - $exempt )",

} else {

  $count_query = "SELECT COUNT(*), ";

  if ( $use_usage eq 'recurring' ) {
    $count_query .= "SUM(setup + recur - usage)";
  } elsif ( $use_usage eq 'usage' ) {
    $count_query .= "SUM(usage)";
  } else {
    $count_query .= "SUM(cust_bill_pkg.setup + cust_bill_pkg.recur)";
  }

}

my $where = ' WHERE '. join(' AND ', @where);

my $join_cust =  '      JOIN cust_bill USING ( invnum ) 
                   LEFT JOIN cust_main USING ( custnum ) ';


my $join_pkg;
if ( $cgi->param('nottax') ) {

  $join_pkg =  ' LEFT JOIN cust_pkg USING ( pkgnum )
                 LEFT JOIN part_pkg USING ( pkgpart )
                 LEFT JOIN part_pkg AS override
                   ON pkgpart_override = override.pkgpart ';
  $join_pkg .= ' LEFT JOIN cust_location USING ( locationnum ) '
    if $conf->exists('tax-pkg_address');

} elsif ( $cgi->param('istax') ) {

  #false laziness w/report_tax.cgi $taxfromwhere
  if ( $conf->exists('tax-pkg_address') ) {
    $join_pkg .= ' LEFT JOIN cust_bill_pkg_tax_location USING ( billpkgnum )
                   LEFT JOIN cust_location              USING ( locationnum ) ';

    #quelle kludge, false laziness w/report_tax.cgi
    $where =~ s/cust_pkg\.locationnum/cust_bill_pkg_tax_location.locationnum/g; 
  } elsif ( scalar( grep( /locationtaxid/, $cgi->param ) ) ) {
    $join_pkg .=
      ' LEFT JOIN cust_bill_pkg_tax_rate_location USING ( billpkgnum ) '.
      ' LEFT JOIN tax_rate_location USING ( taxratelocationnum ) ';
  }

} else { 

  #die?
  warn "neiether nottax nor istax parameters specified";
  #same as before?
  $join_pkg =  ' LEFT JOIN cust_pkg USING ( pkgnum )
                 LEFT JOIN part_pkg USING ( pkgpart ) ';

}

if ($use_usage) {
  $count_query .=
    " FROM (SELECT cust_bill_pkg.setup, cust_bill_pkg.recur, 
             ( SELECT COALESCE( SUM(amount), 0 ) FROM cust_bill_pkg_detail
               WHERE cust_bill_pkg.billpkgnum = cust_bill_pkg_detail.billpkgnum
             ) AS usage FROM cust_bill_pkg  $join_cust $join_pkg $where
           ) AS countquery";
} else {
  $count_query .= " FROM cust_bill_pkg $join_cust $join_pkg $where";
}
warn "count_query is $count_query\n";

my @select = (
               'cust_bill_pkg.*',
               'cust_bill._date',
             );
push @select, 'part_pkg.pkg' unless $cgi->param('istax');
push @select, 'cust_main.custnum',
              FS::UI::Web::cust_sql_fields();

my $query = {
  'table'     => 'cust_bill_pkg',
  'addl_from' => "$join_cust $join_pkg",
  'hashref'   => {},
  'select'    => join(', ', @select ),
  'extra_sql' => $where,
  'order_by'  => 'ORDER BY _date, billpkgnum',
};

my $ilink = [ "${p}view/cust_bill.cgi?", 'invnum' ];
my $clink = [ "${p}view/cust_main.cgi?", 'custnum' ];

my $conf = new FS::Conf;
my $money_char = $conf->config('money_char') || '$';

</%init>
