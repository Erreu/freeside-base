%
%
%  my $fh = $cgi->upload('csvfile');
%  #warn $cgi;
%  #warn $fh;
%
%  my $error = FS::transaction810::testing( {
%        filehandle => $fh,
%        'format'   => scalar($cgi->param('format')),
%      } );
%
%  if ( $error ) {
%    

<b><% $error %></b> 
%
%  } else {
%    
<b>Not Successful!</b>
%
%  }
%

