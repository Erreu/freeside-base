package FS::msg_template::InitialData;

sub _initial_data {
  [
    { msgname   => 'Password reset',
      msgclass  => 'email',
      mime_type => 'text/html', #multipart/alternative with a text part?
                                  # cranky mutt/pine users like me are rare

      _conf        => 'selfservice-password_reset_msgnum',
      _insert_args => [ subject => '{ $company_name } password reset',
                        body    => <<'END',
To complete your { $company_name } password reset, please go to
<a href="{ $selfservice_server_base_url }/selfservice.cgi?action=process_forgot_password_session_{ $session_id }">{ $selfservice_server_base_url }/selfservice.cgi?action=process_forgot_password_session_{ $session_id }</a><br />
<br />
This link will expire in 24 hours.<br />
<br />
If you did not request this password reset, you may safely ignore and delete this message.<br />
<br />
<br />
{ $company_name } Support
END
                      ],
    },
    { msgname   => 'Refund receipt',
      msgclass  => 'email',
      mime_type => 'text/html',
      _conf        => 'refund_receipt_msgnum',
      _insert_args => [ subject => '{ $company_name } refund receipt',
                        body    => <<'END',
Dear {$first} {$last},<BR>
<BR>
The following refund has been applied to your account.<BR>
<BR>
Refund ID: {$refundnum}<BR>
Date:      {$date}<BR>
Amount:    {$refund}<BR>

END
                      ],
    },
  ];
}

1;
