package FS::otaker_Mixin;

use strict;
use Carp qw( croak ); #confess );
use FS::Record qw( qsearch qsearchs );
use FS::access_user;

sub otaker {
  my $self = shift;
  if ( scalar(@_) ) { #set
    my $otaker = shift;
    my $access_user = qsearchs('access_user', { 'username' => $otaker } )
      or croak "can't set otaker: $otaker not found!"; #confess?
    $self->usernum( $access_user->usernum );
    $otaker; #not sure return is used anywhere, but just in case
  } else { #get
    if ( $self->usernum ) {
      $self->access_user->username;
    } elsif ( length($self->get('otaker')) ) {
      $self->get('otaker');
    } else {
      '';
    }
  }
}

sub access_user {
  my $self = shift;
  qsearchs('access_user', { 'usernum' => $self->usernum } );
}

sub _upgrade_otaker {
  my $class = shift;
  my $table = $class->table;

  while ( 1 ) {
    my @records = qsearch({
                    'table'     => $table,
                    'hashref'   => {},
                    'extra_sql' => 'WHERE otaker IS NOT NULL LIMIT 1000',
                  });
    last unless @records;

    foreach my $record (@records) {
      eval { $record->otaker($record->otaker) };
      if ( $@ ) {
        my $access_user = new FS::access_user {
          'username'  => $record->otaker,
          '_password' => 'CHANGEME',
          'first'     => 'Legacy',
          'last'      => 'User',
          'disabled'  => 'Y',
        };
        my $error = $access_user->insert;
        die $error if $error;
        $record->otaker($record->otaker);
      }
      $record->set('otaker', '');
      my $error = $record->replace;
      die $error if $error;
    }

  }

}

1;
