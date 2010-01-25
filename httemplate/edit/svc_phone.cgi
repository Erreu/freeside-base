<% include( 'elements/svc_Common.html',
               'name'     => 'Phone number',
               'table'    => 'svc_phone',
               'fields'   => [ 'countrycode',
                               { field => 'phonenum',
                                 type  => 'select-did',
                                 label => 'Phone number',
                               },
                               { field => 'pbxsvc',
                                 type  => 'select-svc_pbx',
                                 label => 'PBX',
                               },
                               'sip_password',
                               'pin',
                               'phone_name',
                             ],
               'labels'   => {
                               'countrycode'  => 'Country code',
                               'phonenum'     => 'Phone number',
                               'sip_password' => 'SIP password',
                               'pin'          => 'Voicemail PIN',
                               'phone_name'   => 'Name',
                               'pbxsvc'       => 'PBX',
                             },
           )
%>
<%init>

die "access denied"
  unless $FS::CurrentUser::CurrentUser->access_right('Provision customer service'); #something else more specific?

</%init>
