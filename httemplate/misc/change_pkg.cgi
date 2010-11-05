<% include('/elements/header-popup.html', "Change Package") %>

<% include('/elements/error.html') %>

<FORM NAME="OrderPkgForm" ACTION="<% $p %>edit/process/change-cust_pkg.html" METHOD=POST>
<INPUT TYPE="hidden" NAME="pkgnum" VALUE="<% $pkgnum %>">

<% ntable('#cccccc') %>

  <TR>
    <TH ALIGN="right">Current package</TH>
    <TD COLSPAN=7>
      <% $curuser->option('show_pkgnum') ? $cust_pkg->pkgnum.': ' : '' %><B><% $part_pkg->pkg |h %></B> - <% $part_pkg->comment |h %>
    </TD>
  </TR>

  <% include('/elements/tr-select-cust-part_pkg.html',
               'pre_label'  => 'New',
               'curr_value' => scalar($cgi->param('pkgpart')),
               'classnum'   => $part_pkg->classnum,
               'cust_main'  => $cust_main,
               #'extra_sql'    => ' AND pkgpart != '. $cust_pkg->pkgpart,
            )
  %>

  <% include('/elements/tr-select-cust_location.html',
               'cgi'       => $cgi,
               'cust_main' => $cust_main,
            )
  %>

</TABLE>

<% include( '/elements/standardize_locations.html',
            'form'       => "OrderPkgForm",
            'onlyship'   => 1,
            'no_company' => 1,
            'callback'   => 'document.OrderPkgForm.submit();',
          )
%>

<BR>
<INPUT NAME="submitButton" TYPE="button" VALUE="Change package" onClick="this.disabled=true; standardize_locations();">

</FORM>
</BODY>
</HTML>

<%init>

my $conf = new FS::Conf;

my $curuser = $FS::CurrentUser::CurrentUser;

die "access denied"
  unless $curuser->access_right('Change customer package');

my $pkgnum = scalar($cgi->param('pkgnum'));
$pkgnum =~ /^(\d+)$/ or die "illegal pkgnum $pkgnum";
$pkgnum = $1;

my $cust_pkg =
  qsearchs({
    'table'     => 'cust_pkg',
    'addl_from' => 'LEFT JOIN cust_main USING ( custnum )',
    'hashref'   => { 'pkgnum' => $pkgnum },
    'extra_sql' => ' AND '. $curuser->agentnums_sql,
  }) or die "unknown pkgnum $pkgnum";

my $cust_main = $cust_pkg->cust_main
  or die "can't get cust_main record for custnum ". $cust_pkg->custnum.
         " ( pkgnum ". cust_pkg->pkgnum. ")";

my $part_pkg = $cust_pkg->part_pkg;

</%init>
