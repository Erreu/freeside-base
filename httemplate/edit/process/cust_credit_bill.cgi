<% include('elements/ApplicationCommon.html',
     'form_action' => 'process/cust_credit_bill.cgi',
     'src_table'   => 'cust_credit',
     'src_thing'   => 'credit',
     'dst_table'   => 'cust_bill',
     'dst_thing'   => 'invoice',
   )
%>
<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Apply credit');

</%init>
