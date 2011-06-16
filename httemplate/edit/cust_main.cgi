<% include('/elements/header.html',
      $title,
      '',
      ' onUnload="myclose()"' #hmm, in billing.html
) %>

<% include('/elements/error.html') %>

<FORM NAME   = "CustomerForm"
      METHOD = "POST"
      ACTION = "<% popurl(1) %>process/cust_main.cgi"
%#      STYLE = "margin-bottom: 0"
%#      STYLE="margin-top: 0; margin-bottom: 0">
>

<INPUT TYPE="hidden" NAME="custnum" VALUE="<% $custnum %>">

% if ( $custnum ) { 
  Customer #<B><% $cust_main->display_custnum %></B> - 
  <B><FONT COLOR="#<% $cust_main->statuscolor %>">
    <% ucfirst($cust_main->status) %>
  </FONT></B>
  <BR><BR>
% } 

%# agent, agent_custid, refnum (advertising source), referral_custnum
<% include('cust_main/top_misc.html', $cust_main, 'custnum' => $custnum ) %>

%# birthdate
% if ( $conf->exists('cust_main-enable_birthdate') ) {
  <BR>
  <% include('cust_main/birthdate.html', $cust_main) %>
% }

%# latitude and longitude
% if ( $conf->exists('cust_main-require_censustract') ) {
%   my ($latitude, $longitude) = $cust_main->service_coordinates;
%   $latitude ||= $conf->config('company_latitude') || '';
%   $longitude ||= $conf->config('company_longitude') || '';
  <INPUT NAME="latitude" TYPE="hidden" VALUE="<% $latitude |h %>">
  <INPUT NAME="longitude" TYPE="hidden" VALUE="<% $longitude |h %>">
% }

%# contact info

%  my $same_checked = '';
%  my $ship_disabled = '';
%  my @ship_style = ();
%  unless ( $cust_main->ship_last && $same ne 'Y' ) {
%    $same_checked = 'CHECKED';
%    $ship_disabled = 'DISABLED';
%    push @ship_style, 'background-color:#dddddd';
%    foreach (
%      qw( last first company address1 address2 city county state zip country
%          daytime night fax )
%    ) {
%      $cust_main->set("ship_$_", $cust_main->get($_) );
%    }
%  }

<BR>
<FONT SIZE="+1"><B>Billing address</B></FONT>

<% include('cust_main/contact.html',
             'cust_main'    => $cust_main,
             'pre'          => '',
             'onchange'     => 'bill_changed(this)',
             'disabled'     => '',
             'ss'           => $ss,
             'stateid'      => $stateid,
             'same_checked' => $same_checked, #for address2 "Unit #" labeling
          )
%>

<SCRIPT>
function bill_changed(what) {
  if ( what.form.same.checked ) {
% for (qw( last first company address1 address2 city zip daytime night fax )) { 
    what.form.ship_<%$_%>.value = what.form.<%$_%>.value;
% } 

    what.form.ship_country.selectedIndex = what.form.country.selectedIndex;

    function fix_ship_city() {
      what.form.ship_city_select.selectedIndex = what.form.city_select.selectedIndex;
      what.form.ship_city.style.display = what.form.city.style.display;
      what.form.ship_city_select.style.display = what.form.city_select.style.display;
    }

    function fix_ship_county() {
      what.form.ship_county.selectedIndex = what.form.county.selectedIndex;
      ship_county_changed(what.form.ship_county, fix_ship_city );
    }

    function fix_ship_state() {
      what.form.ship_state.selectedIndex = what.form.state.selectedIndex;
      ship_state_changed(what.form.ship_state, fix_ship_county );
    }

    ship_country_changed(what.form.ship_country, fix_ship_state );

  }
}
function samechanged(what) {
  if ( what.checked ) {
    bill_changed(what);

%   my @fields = qw( last first company address1 address2 city city_select county state zip country daytime night fax );
%   for (@fields) { 
      what.form.ship_<%$_%>.disabled = true;
      what.form.ship_<%$_%>.style.backgroundColor = '#dddddd';
%   } 

%   if ( $conf->exists('cust_main-require_address2') ) {
      document.getElementById('address2_required').style.visibility = '';
      document.getElementById('address2_label').style.visibility = '';
      document.getElementById('ship_address2_required').style.visibility = 'hidden';
      document.getElementById('ship_address2_label').style.visibility = 'hidden';
%   }

  } else {

%   for (@fields) { 
      what.form.ship_<%$_%>.disabled = false;
      what.form.ship_<%$_%>.style.backgroundColor = '#ffffff';
%   } 

%   if ( $conf->exists('cust_main-require_address2') ) {
      document.getElementById('address2_required').style.visibility = 'hidden';
      document.getElementById('address2_label').style.visibility = 'hidden';
      document.getElementById('ship_address2_required').style.visibility = '';
      document.getElementById('ship_address2_label').style.visibility = '';
%   }

  }
}
</SCRIPT>

<BR>
<FONT SIZE="+1"><B>Service address</B></FONT>

(<INPUT TYPE="checkbox" NAME="same" VALUE="Y" onClick="samechanged(this)" <%$same_checked%>>same as billing address)
<% include('cust_main/contact.html',
             'cust_main' => $cust_main,
             'pre'       => 'ship_',
             'onchange'  => '',
             'disabled'  => $ship_disabled,
             'style'     => \@ship_style
          )
%>

%# billing info
<% include( 'cust_main/billing.html', $cust_main,
               'payinfo'        => $payinfo,
               'invoicing_list' => \@invoicing_list,
           )
%>

% my $ro_comments = $conf->exists('cust_main-use_comments')?'':'readonly';
% if (!$ro_comments || $cust_main->comments) {

    <BR>Comments
    <% &ntable("#cccccc") %>
      <TR>
        <TD>
          <TEXTAREA NAME = "comments"
                    COLS = 80
                    ROWS = 5
                    WRAP = "HARD"
                    <% $ro_comments %>
          ><% $cust_main->comments %></TEXTAREA>
        </TD>
      </TR>
    </TABLE>

% }

% unless ( $custnum ) {

    <% include('cust_main/first_pkg.html', $cust_main,
                 'pkgpart_svcpart' => $pkgpart_svcpart,
                 'disable_empty'   =>
                   scalar( $cgi->param('lock_pkgpart') =~ /^(\d+)$/ ),
                 #svc_acct
                 'username'        => $username,
                 'password'        => $password,
                 'popnum'          => $popnum,
                 'saved_domsvc'    => $saved_domsvc,
                 %svc_phone,
              )
    %>

% }

<INPUT TYPE="hidden" NAME="usernum" VALUE="<% $cust_main->usernum %>">

%# cust_main/bottomfixup.js
% foreach my $hidden (
%    'payauto',
%    'payinfo', 'payinfo1', 'payinfo2', 'paytype',
%    'payname', 'paystate', 'exp_month', 'exp_year', 'paycvv',
%    'paystart_month', 'paystart_year', 'payissue',
%    'payip',
%    'paid',
% ) {
    <INPUT TYPE="hidden" NAME="<% $hidden %>" VALUE="">
% } 

<% include('cust_main/bottomfixup.html') %>

<BR>
<INPUT TYPE    = "button"
       NAME    = "submitButton"
       ID      = "submitButton"
       VALUE   = "<% $custnum ?  "Apply Changes" : "Add Customer" %>"
       onClick = "this.disabled=true; bottomfixup(this.form);"
>
</FORM>

<% include('/elements/footer.html') %>

<%init>

my $curuser = $FS::CurrentUser::CurrentUser;

#probably redundant given the checks below...
die "access denied"
  unless $curuser->access_right('New customer')
     ||  $curuser->access_right('Edit customer');

my $conf = new FS::Conf;

#get record

my($custnum, $cust_main, $ss, $stateid, $payinfo, @invoicing_list);
my $same = '';
my $pkgpart_svcpart = ''; #first_pkg
my($username, $password, $popnum, $saved_domsvc) = ( '', '', 0, 0 ); #svc_acct
my %svc_phone = ();

if ( $cgi->param('error') ) {

  $cust_main = new FS::cust_main ( {
    map { $_, scalar($cgi->param($_)) } fields('cust_main')
  } );

  $custnum = $cust_main->custnum;

  die "access denied"
    unless $curuser->access_right($custnum ? 'Edit customer' : 'New customer');

  @invoicing_list = split( /\s*,\s*/, $cgi->param('invoicing_list') );
  $same = $cgi->param('same');
  $cust_main->setfield('paid' => $cgi->param('paid')) if $cgi->param('paid');
  $ss = $cust_main->ss;           # don't mask an entered value on errors
  $stateid = $cust_main->stateid; # don't mask an entered value on errors
  $payinfo = $cust_main->payinfo; # don't mask an entered value on errors

  $pkgpart_svcpart = $cgi->param('pkgpart_svcpart') || '';

  #svc_acct
  $username = $cgi->param('username');
  $password = $cgi->param('_password');
  $popnum = $cgi->param('popnum');
  $saved_domsvc = $cgi->param('domsvc') || '';
  if ( $saved_domsvc =~ /^(\d+)$/ ) {
    $saved_domsvc = $1;
  } else {
    $saved_domsvc = '';
  }

  #svc_phone
  $svc_phone{$_} = $cgi->param($_)
    foreach qw( countrycode phonenum sip_password pin phone_name );

} elsif ( $cgi->keywords ) { #editing

  die "access denied"
    unless $curuser->access_right('Edit customer');

  my( $query ) = $cgi->keywords;
  $query =~ /^(\d+)$/;
  $custnum=$1;
  $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } );
  if ( $cust_main->dbdef_table->column('paycvv')
       && length($cust_main->paycvv)             ) {
    my $paycvv = $cust_main->paycvv;
    $paycvv =~ s/./*/g;
    $cust_main->paycvv($paycvv);
  }
  @invoicing_list = $cust_main->invoicing_list;
  $ss = $cust_main->masked('ss');
  $stateid = $cust_main->masked('stateid');
  $payinfo = $cust_main->paymask;

} else { #new customer

  die "access denied"
    unless $curuser->access_right('New customer');

  $custnum='';
  $cust_main = new FS::cust_main ( {} );
  $cust_main->agentnum( $conf->config('default_agentnum') )
    if $conf->exists('default_agentnum');
  $cust_main->otaker( &getotaker );
  $cust_main->referral_custnum( $cgi->param('referral_custnum') );
  @invoicing_list = ();
  push @invoicing_list, 'POST'
    unless $conf->exists('disablepostalinvoicedefault');
  $ss = '';
  $stateid = '';
  $payinfo = '';

  if ( $cgi->param('lock_pkgpart') =~ /^(\d+)$/ ) {
    my $pkgpart = $1;
    my $part_pkg = qsearchs('part_pkg', { 'pkgpart' => $pkgpart } )
      or die "unknown pkgpart $pkgpart";
    my $svcpart = $part_pkg->svcpart;
    $pkgpart_svcpart = $pkgpart.'_'.$svcpart;
  }

}

my %keep = map { $_=>1 } qw( error tagnum lock_agentnum lock_pkgpart );
$cgi->delete( grep !$keep{$_}, $cgi->param );

my $title = $custnum ? 'Edit Customer' : 'Add Customer';
$title .= ": ". $cust_main->name if $custnum;

my $r = qq!<font color="#ff0000">*</font>&nbsp;!;

</%init>
