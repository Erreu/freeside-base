<% include('/elements/header.html', "$action $svc", '') %>

<% include('/elements/error.html') %>

<FORM ACTION="<% $p1 %>process/svc_cert.cgi" METHOD=POST>
<INPUT TYPE="hidden" NAME="svcnum" VALUE="<% $svcnum %>">
<INPUT TYPE="hidden" NAME="pkgnum" VALUE="<% $pkgnum %>">
<INPUT TYPE="hidden" NAME="svcpart" VALUE="<% $svcpart %>">

<% ntable("#cccccc",2) %>

</TABLE>
<BR>

<INPUT TYPE="submit" VALUE="Submit">

</FORM>

<% include('/elements/footer.html') %>

<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Provision customer service'); #something else more specific?

#my $conf = new FS::Conf;



</%init>
