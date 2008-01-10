<% include( 'elements/browse.html',
              'title'       => 'Rate plans',
              'menubar'     => [ 'Regions and Prefixes' =>
                                   $p.'browse/rate_region.html',
                               ],
              'html_init'   => $html_init,
              'name'        => 'rate plans',
              'query'       => { 'table'     => 'rate',
                                 'hashref'   => {},
                                 'extra_sql' => 'ORDER BY ratenum',
                               },
              'count_query' => $count_query,
              'header'      => [ '#',       'Rate plan', 'Rates'    ],
              'fields'      => [ 'ratenum', 'ratename',  $rates_sub ],
              'links'       => [ $link,     $link,       ''         ],
          )
%>
<%once>

my $sth = dbh->prepare("SELECT DISTINCT(countrycode) FROM rate_prefix")
  or die dbh->errstr;
$sth->execute or die $sth->errstr;
my @all_countrycodes = map $_->[0], @{ $sth->fetchall_arrayref };
my $all_countrycodes = join("\n", map qq(<OPTION VALUE="$_">$_),
                                      @all_countrycodes
                           );

my $rates_sub = sub {
  my $rate = shift;
  my $ratenum = $rate->ratenum;

  qq( <FORM METHOD="GET" ACTION="${p}browse/rate_detail.html">
        <INPUT TYPE="hidden" NAME="ratenum" VALUE="$ratenum">
        <SELECT NAME="countrycode" onChange="this.form.submit();">
          <OPTION SELECTED>Select Country Code
          <OPTION VALUE="">(all)
          $all_countrycodes
        </SELECT>
      </FORM>
    );


};

</%once>
<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Configuration');

my $html_init = 
  'Rate plans for VoIP and call billing.<BR><BR>'.
  qq!<A HREF="${p}edit/rate.cgi"><I>Add a rate plan</I></A>!.
  '<BR><BR>
   <SCRIPT>
   function rate_areyousure(href) {
    if (confirm("Are you sure you want to delete this rate plan?") == true)
      window.location.href = href;
   }
   </SCRIPT>
  ';

my $count_query = 'SELECT COUNT(*) FROM rate';

my $link = [ $p.'edit/rate.cgi?', 'ratenum' ];

</%init>
