<%
   my $title = 'Payment Search Results';
   my( $count_query, $sql_query );
   if ( $cgi->param('magic') ) {

     my @search = ();
     my $orderby;
     if ( $cgi->param('magic') eq '_date' ) {
   
  
       if ( $cgi->param('agentnum') && $cgi->param('agentnum') =~ /^(\d+)$/ ) {
         push @search, "agentnum = $1"; # $search{'agentnum'} = $1;
         my $agent = qsearchs('agent', { 'agentnum' => $1 } );
         die "unknown agentnum $1" unless $agent;
         $title = $agent->agent. " $title";
       }
     
       if ( $cgi->param('payby') ) {
         $cgi->param('payby') =~
           /^(CARD|CHEK|BILL|PREP|CASH|WEST|MCRD)(-(VisaMC|Amex|Discover|Maestro))?$/
             or die "illegal payby ". $cgi->param('payby');
         push @search, "cust_pay.payby = '$1'";
         if ( $3 ) {
           if ( $3 eq 'VisaMC' ) {
             #avoid posix regexes for portability
             push @search,
               " ( (     substring(cust_pay.payinfo from 1 for 1) = '4'     ".
               "     AND substring(cust_pay.payinfo from 1 for 4) != '4936' ".
               "     AND substring(cust_pay.payinfo from 1 for 6)           ".
               "         NOT SIMILAR TO '49030[2-9]'                        ".
               "     AND substring(cust_pay.payinfo from 1 for 6)           ".
               "         NOT SIMILAR TO '49033[5-9]'                        ".
               "     AND substring(cust_pay.payinfo from 1 for 6)           ".
               "         NOT SIMILAR TO '49110[1-2]'                        ".
               "     AND substring(cust_pay.payinfo from 1 for 6)           ".
               "         NOT SIMILAR TO '49117[4-9]'                        ".
               "     AND substring(cust_pay.payinfo from 1 for 6)           ".
               "         NOT SIMILAR TO '49118[1-2]'                        ".
               "   )".
               "   OR substring(cust_pay.payinfo from 1 for 2) = '51' ".
               "   OR substring(cust_pay.payinfo from 1 for 2) = '52' ".
               "   OR substring(cust_pay.payinfo from 1 for 2) = '53' ".
               "   OR substring(cust_pay.payinfo from 1 for 2) = '54' ".
               "   OR substring(cust_pay.payinfo from 1 for 2) = '54' ".
               "   OR substring(cust_pay.payinfo from 1 for 2) = '55' ".
               " ) ";
           } elsif ( $3 eq 'Amex' ) {
             push @search,
               " (    substring(cust_pay.payinfo from 1 for 2 ) = '34' ".
               "   OR substring(cust_pay.payinfo from 1 for 2 ) = '37' ".
               " ) ";
           } elsif ( $3 eq 'Discover' ) {
             push @search,
               " (    substring(cust_pay.payinfo from 1 for 4 ) = '6011'  ".
               "   OR substring(cust_pay.payinfo from 1 for 3 ) = '650'   ".
               " ) ";
           } elsif ( $3 eq 'Maestro' ) { 
             push @search,
               " (    substring(cust_pay.payinfo from 1 for 2 ) = '63'     ".
               "   OR substring(cust_pay.payinfo from 1 for 2 ) = '67'     ".
               "   OR substring(cust_pay.payinfo from 1 for 6 ) = '564182' ".
               "   OR substring(cust_pay.payinfo from 1 for 4 ) = '4936'   ".
               "   OR substring(cust_pay.payinfo from 1 for 6 )            ".
               "      SIMILAR TO '49030[2-9]'                             ".
               "   OR substring(cust_pay.payinfo from 1 for 6 )            ".
               "      SIMILAR TO '49033[5-9]'                             ".
               "   OR substring(cust_pay.payinfo from 1 for 6 )            ".
               "      SIMILAR TO '49110[1-2]'                             ".
               "   OR substring(cust_pay.payinfo from 1 for 6 )            ".
               "      SIMILAR TO '49117[4-9]'                             ".
               "   OR substring(cust_pay.payinfo from 1 for 6 )            ".
               "      SIMILAR TO '49118[1-2]'                             ".
               " ) ";
           } else {
             die "unknown card type $3";
           }
         }
       }
  
       my($beginning, $ending) = FS::UI::Web::parse_beginning_ending($cgi);
       push @search, "_date >= $beginning ",
                     "_date <= $ending";
  
       $orderby = '_date';
   
     } elsif ( $cgi->param('magic') eq 'paybatch' ) {

       $cgi->param('paybatch') =~ /^([\w\/\:\-\.]+)$/
         or die "illegal paybatch: ". $cgi->param('paybatch');

       push @search, "paybatch = '$1'";

       $orderby = "LOWER(company || ' ' || last || ' ' || first )";

     } else {
       die "unknown search magic: ". $cgi->param('magic');
     }

     my $search = '';
     if ( @search ) {
       $search = ' WHERE '. join(' AND ', @search);
     }
  
     $count_query = "SELECT COUNT(*), SUM(paid) ".
                    "FROM cust_pay LEFT JOIN cust_main USING ( custnum )".
                    $search;

     $sql_query = {
       'table'     => 'cust_pay',
       'select'    => join(', ',
                        'cust_pay.*',
                        'cust_main.custnum as cust_main_custnum',
                        FS::UI::Web::cust_sql_fields(),
                      ),
       'hashref'   => {},
       'extra_sql' => "$search ORDER BY $orderby",
       'addl_from' => 'LEFT JOIN cust_main USING ( custnum )',
     };

   } else {
   
     $cgi->param('payinfo') =~ /^\s*(\d+)\s*$/ or die "illegal payinfo";
     my $payinfo = $1;
   
     $cgi->param('payby') =~ /^(\w+)$/ or die "illegal payby";
     my $payby = $1;
   
     $count_query = "SELECT COUNT(*), SUM(paid) FROM cust_pay ".
                    "WHERE payinfo = '$payinfo' AND payby = '$payby'";
   
     $sql_query = {
       'table'     => 'cust_pay',
       'hashref'   => { 'payinfo' => $payinfo,
                        'payby'   => $payby    },
       'extra_sql' => "ORDER BY _date",
     };
   
   }

   my $link = sub {
     my $cust_pay = shift;
     $cust_pay->cust_main_custnum
       ? [ "${p}view/cust_main.cgi?", 'custnum' ] 
       : '';
   };

%><%= include( 'elements/search.html',
                 'title'       => $title,
                 'name'        => 'payments',
                 'query'       => $sql_query,
                 'count_query' => $count_query,
                 'count_addl'  => [ '$%.2f total paid', ],
                 'header'      => [ 'Payment',
                                    'Amount',
                                    'Date',
                                    FS::UI::Web::cust_header(),
                                  ],
                 'fields'      => [
                   sub {
                     my $cust_pay = shift;
                     if ( $cust_pay->payby eq 'CARD' ) {
                       'Card #'. $cust_pay->payinfo_masked;
                     } elsif ( $cust_pay->payby eq 'CHEK' ) {
                       'E-check acct#'. $cust_pay->payinfo;
                     } elsif ( $cust_pay->payby eq 'BILL' ) {
                       'Check #'. $cust_pay->payinfo;
                     } elsif ( $cust_pay->payby eq 'PREP' ) {
                       'Prepaid card #'. $cust_pay->payinfo;
                     } elsif ( $cust_pay->payby eq 'CASH' ) {
                       'Cash '. $cust_pay->payinfo;
                     } elsif ( $cust_pay->payby eq 'WEST' ) {
                       'Western Union'; #. $cust_pay->payinfo;
                     } elsif ( $cust_pay->payby eq 'MCRD' ) {
                       'Manual credit card'; #. $cust_pay->payinfo;
                     } else {
                       $cust_pay->payby. ' '. $cust_pay->payinfo;
                     }
                   },
                   sub { sprintf('$%.2f', shift->paid ) },
                   sub { time2str('%b %d %Y', shift->_date ) },
                   \&FS::UI::Web::cust_fields,
                 ],
                 #'align' => 'lrrrll',
                 'align' => 'rrr',
                 'links' => [
                   '',
                   '',
                   '',
                   ( map { $link } FS::UI::Web::cust_header() ),
                 ],
      )
%>
