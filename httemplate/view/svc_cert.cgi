<% include('elements/svc_Common.html',
             'table'     => 'svc_pbx',
             'edit_url'  => $p."edit/svc_Common.html?svcdb=svc_pbx;svcnum=",
             #'labels'    => \%labels,
             #'html_foot' => $html_foot,
             'fields' => []
          )
%>
<%init>

#my $fields = FS::svc_pbx->table_info->{'fields'};
#my %labels = map { $_ =>  ( ref($fields->{$_})
#                             ? $fields->{$_}{'label'}
#                             : $fields->{$_}
#                         );
#                 }
#             keys %$fields;

</%init>
