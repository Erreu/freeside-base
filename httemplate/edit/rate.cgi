<% include("/elements/header.html","$action Rate plan", menubar(
      'Main Menu' => $p,
      'View all rate plans' => "${p}browse/rate.cgi",
    ))
%>

<% include('/elements/progress-init.html',
              'OneTrueForm',
              [ 'rate', 'min_', 'sec_' ],
              'process/rate.cgi',
              $p.'browse/rate.cgi',
           )
%>
<FORM NAME="OneTrueForm">
<INPUT TYPE="hidden" NAME="ratenum" VALUE="<% $rate->ratenum %>">

Rate plan
<INPUT TYPE="text" NAME="ratename" SIZE=32 VALUE="<% $rate->ratename %>">
<BR><BR>

<INPUT NAME="submit" TYPE="button" VALUE="<% 
  $rate->ratenum ? "Apply changes" : "Add rate plan"
%>" onClick="document.OneTrueForm.submit.disabled=true; process();">

</FORM>

<% include('/elements/footer.html') %>

<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Configuration');

my $rate;
if ( $cgi->keywords ) {
  my($query) = $cgi->keywords;
  $query =~ /^(\d+)$/;
  $rate = qsearchs( 'rate', { 'ratenum' => $1 } );
} else { #adding
  $rate = new FS::rate {};
}
my $action = $rate->ratenum ? 'Edit' : 'Add';

</%init>
