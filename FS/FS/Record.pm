package FS::Record;

use strict;
use vars qw( $AUTOLOAD @ISA @EXPORT_OK $DEBUG
             $conf $me
             %virtual_fields_cache $nowarn_identical $no_update_diff );
use Exporter;
use Carp qw(carp cluck croak confess);
use File::CounterFile;
use Locale::Country;
use DBI qw(:sql_types);
use DBIx::DBSchema 0.25;
#use DBIx::DBSchema 0.33; #when check for ->can('unique_singles') is sub insert
                          #is removed
use FS::UID qw(dbh getotaker datasrc driver_name);
use FS::CurrentUser;
use FS::Schema qw(dbdef);
use FS::SearchCache;
use FS::Msgcat qw(gettext);
use FS::Conf;

use FS::part_virtual_field;

use Tie::IxHash;

@ISA = qw(Exporter);

#export dbdef for now... everything else expects to find it here
@EXPORT_OK = qw(dbh fields hfields qsearch qsearchs dbdef jsearch str2time_sql);

$DEBUG = 0;
$me = '[FS::Record]';

$nowarn_identical = 0;
$no_update_diff = 0;

my $rsa_module;
my $rsa_loaded;
my $rsa_encrypt;
my $rsa_decrypt;

FS::UID->install_callback( sub {
  $conf = new FS::Conf; 
  $File::CounterFile::DEFAULT_DIR = $conf->base_dir . "/counters.". datasrc;
} );


=head1 NAME

FS::Record - Database record objects

=head1 SYNOPSIS

    use FS::Record;
    use FS::Record qw(dbh fields qsearch qsearchs);

    $record = new FS::Record 'table', \%hash;
    $record = new FS::Record 'table', { 'column' => 'value', ... };

    $record  = qsearchs FS::Record 'table', \%hash;
    $record  = qsearchs FS::Record 'table', { 'column' => 'value', ... };
    @records = qsearch  FS::Record 'table', \%hash; 
    @records = qsearch  FS::Record 'table', { 'column' => 'value', ... };

    $table = $record->table;
    $dbdef_table = $record->dbdef_table;

    $value = $record->get('column');
    $value = $record->getfield('column');
    $value = $record->column;

    $record->set( 'column' => 'value' );
    $record->setfield( 'column' => 'value' );
    $record->column('value');

    %hash = $record->hash;

    $hashref = $record->hashref;

    $error = $record->insert;

    $error = $record->delete;

    $error = $new_record->replace($old_record);

    # external use deprecated - handled by the database (at least for Pg, mysql)
    $value = $record->unique('column');

    $error = $record->ut_float('column');
    $error = $record->ut_floatn('column');
    $error = $record->ut_number('column');
    $error = $record->ut_numbern('column');
    $error = $record->ut_snumber('column');
    $error = $record->ut_snumbern('column');
    $error = $record->ut_money('column');
    $error = $record->ut_text('column');
    $error = $record->ut_textn('column');
    $error = $record->ut_alpha('column');
    $error = $record->ut_alphan('column');
    $error = $record->ut_phonen('column');
    $error = $record->ut_anything('column');
    $error = $record->ut_name('column');

    $quoted_value = _quote($value,'table','field');

    #deprecated
    $fields = hfields('table');
    if ( $fields->{Field} ) { # etc.

    @fields = fields 'table'; #as a subroutine
    @fields = $record->fields; #as a method call


=head1 DESCRIPTION

(Mostly) object-oriented interface to database records.  Records are currently
implemented on top of DBI.  FS::Record is intended as a base class for
table-specific classes to inherit from, i.e. FS::cust_main.

=head1 CONSTRUCTORS

=over 4

=item new [ TABLE, ] HASHREF

Creates a new record.  It doesn't store it in the database, though.  See
L<"insert"> for that.

Note that the object stores this hash reference, not a distinct copy of the
hash it points to.  You can ask the object for a copy with the I<hash> 
method.

TABLE can only be omitted when a dervived class overrides the table method.

=cut

sub new { 
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);

  unless ( defined ( $self->table ) ) {
    $self->{'Table'} = shift;
    carp "warning: FS::Record::new called with table name ". $self->{'Table'};
  }
  
  $self->{'Hash'} = shift;

  foreach my $field ( grep !defined($self->{'Hash'}{$_}), $self->fields ) { 
    $self->{'Hash'}{$field}='';
  }

  $self->_rebless if $self->can('_rebless');

  $self->{'modified'} = 0;

  $self->_cache($self->{'Hash'}, shift) if $self->can('_cache') && @_;

  $self;
}

sub new_or_cached {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);

  $self->{'Table'} = shift unless defined ( $self->table );

  my $hashref = $self->{'Hash'} = shift;
  my $cache = shift;
  if ( defined( $cache->cache->{$hashref->{$cache->key}} ) ) {
    my $obj = $cache->cache->{$hashref->{$cache->key}};
    $obj->_cache($hashref, $cache) if $obj->can('_cache');
    $obj;
  } else {
    $cache->cache->{$hashref->{$cache->key}} = $self->new($hashref, $cache);
  }

}

sub create {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);
  if ( defined $self->table ) {
    cluck "create constructor is deprecated, use new!";
    $self->new(@_);
  } else {
    croak "FS::Record::create called (not from a subclass)!";
  }
}

=item qsearch PARAMS_HASHREF | TABLE, HASHREF, SELECT, EXTRA_SQL, CACHE_OBJ, ADDL_FROM

Searches the database for all records matching (at least) the key/value pairs
in HASHREF.  Returns all the records found as `FS::TABLE' objects if that
module is loaded (i.e. via `use FS::cust_main;'), otherwise returns FS::Record
objects.

The preferred usage is to pass a hash reference of named parameters:

  my @records = qsearch( {
                           'table'     => 'table_name',
                           'hashref'   => { 'field' => 'value'
                                            'field' => { 'op'    => '<',
                                                         'value' => '420',
                                                       },
                                          },

                           #these are optional...
                           'select'    => '*',
                           'extra_sql' => 'AND field ',
                           'order_by'  => 'ORDER BY something',
                           #'cache_obj' => '', #optional
                           'addl_from' => 'LEFT JOIN othtable USING ( field )',
                         }
                       );

Much code still uses old-style positional parameters, this is also probably
fine in the common case where there are only two parameters:

  my @records = qsearch( 'table', { 'field' => 'value' } );

###oops, argh, FS::Record::new only lets us create database fields.
#Normal behaviour if SELECT is not specified is `*', as in
#C<SELECT * FROM table WHERE ...>.  However, there is an experimental new
#feature where you can specify SELECT - remember, the objects returned,
#although blessed into the appropriate `FS::TABLE' package, will only have the
#fields you specify.  This might have unwanted results if you then go calling
#regular FS::TABLE methods
#on it.

=cut

sub qsearch {
  my($stable, $record, $select, $extra_sql, $order_by, $cache, $addl_from );
  if ( ref($_[0]) ) { #hashref for now, eventually maybe accept a list too
    my $opt = shift;
    $stable    = $opt->{'table'}     or die "table name is required";
    $record    = $opt->{'hashref'}   || {};
    $select    = $opt->{'select'}    || '*';
    $extra_sql = $opt->{'extra_sql'} || '';
    $order_by  = $opt->{'order_by'}  || '';
    $cache     = $opt->{'cache_obj'} || '';
    $addl_from = $opt->{'addl_from'} || '';
  } else {
    ($stable, $record, $select, $extra_sql, $cache, $addl_from ) = @_;
    $select ||= '*';
  }

  #$stable =~ /^([\w\_]+)$/ or die "Illegal table: $table";
  #for jsearch
  $stable =~ /^([\w\s\(\)\.\,\=]+)$/ or die "Illegal table: $stable";
  $stable = $1;
  my $dbh = dbh;

  my $table = $cache ? $cache->table : $stable;
  my $dbdef_table = dbdef->table($table)
    or die "No schema for table $table found - ".
           "do you need to run freeside-upgrade?";
  my $pkey = $dbdef_table->primary_key;

  my @real_fields = grep exists($record->{$_}), real_fields($table);
  my @virtual_fields;
  if ( eval 'scalar(@FS::'. $table. '::ISA);' ) {
    @virtual_fields = grep exists($record->{$_}), "FS::$table"->virtual_fields;
  } else {
    cluck "warning: FS::$table not loaded; virtual fields not searchable";
    @virtual_fields = ();
  }

  my $statement = "SELECT $select FROM $stable";
  $statement .= " $addl_from" if $addl_from;
  if ( @real_fields or @virtual_fields ) {
    $statement .= ' WHERE '. join(' AND ',
      ( map {

      my $op = '=';
      my $column = $_;
      if ( ref($record->{$_}) ) {
        $op = $record->{$_}{'op'} if $record->{$_}{'op'};
        #$op = 'LIKE' if $op =~ /^ILIKE$/i && driver_name ne 'Pg';
        if ( uc($op) eq 'ILIKE' ) {
          $op = 'LIKE';
          $record->{$_}{'value'} = lc($record->{$_}{'value'});
          $column = "LOWER($_)";
        }
        $record->{$_} = $record->{$_}{'value'}
      }

      if ( ! defined( $record->{$_} ) || $record->{$_} eq '' ) {
        if ( $op eq '=' ) {
          if ( driver_name eq 'Pg' ) {
            my $type = dbdef->table($table)->column($column)->type;
            if ( $type =~ /(int|(big)?serial)/i ) {
              qq-( $column IS NULL )-;
            } else {
              qq-( $column IS NULL OR $column = '' )-;
            }
          } else {
            qq-( $column IS NULL OR $column = "" )-;
          }
        } elsif ( $op eq '!=' ) {
          if ( driver_name eq 'Pg' ) {
            my $type = dbdef->table($table)->column($column)->type;
            if ( $type =~ /(int|(big)?serial)/i ) {
              qq-( $column IS NOT NULL )-;
            } else {
              qq-( $column IS NOT NULL AND $column != '' )-;
            }
          } else {
            qq-( $column IS NOT NULL AND $column != "" )-;
          }
        } else {
          if ( driver_name eq 'Pg' ) {
            qq-( $column $op '' )-;
          } else {
            qq-( $column $op "" )-;
          }
        }
      } else {
        "$column $op ?";
      }
    } @real_fields ), 
    ( map {
      my $op = '=';
      my $column = $_;
      if ( ref($record->{$_}) ) {
        $op = $record->{$_}{'op'} if $record->{$_}{'op'};
	if ( uc($op) eq 'ILIKE' ) {
	  $op = 'LIKE';
	  $record->{$_}{'value'} = lc($record->{$_}{'value'});
	  $column = "LOWER($_)";
	}
	$record->{$_} = $record->{$_}{'value'};
      }

      # ... EXISTS ( SELECT name, value FROM part_virtual_field
      #              JOIN virtual_field
      #              ON part_virtual_field.vfieldpart = virtual_field.vfieldpart
      #              WHERE recnum = svc_acct.svcnum
      #              AND (name, value) = ('egad', 'brain') )

      my $value = $record->{$_};

      my $subq;

      $subq = ($value ? 'EXISTS ' : 'NOT EXISTS ') .
      "( SELECT part_virtual_field.name, virtual_field.value ".
      "FROM part_virtual_field JOIN virtual_field ".
      "ON part_virtual_field.vfieldpart = virtual_field.vfieldpart ".
      "WHERE virtual_field.recnum = ${table}.${pkey} ".
      "AND part_virtual_field.name = '${column}'".
      ($value ? 
        " AND virtual_field.value ${op} '${value}'"
      : "") . ")";
      $subq;

    } @virtual_fields ) );

  }

  $statement .= " $extra_sql" if defined($extra_sql);
  $statement .= " $order_by"  if defined($order_by);

  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = $dbh->prepare($statement)
    or croak "$dbh->errstr doing $statement";

  my $bind = 1;

  foreach my $field (
    grep defined( $record->{$_} ) && $record->{$_} ne '', @real_fields
  ) {
    if ( $record->{$field} =~ /^\d+(\.\d+)?$/
         && dbdef->table($table)->column($field)->type =~ /(int|(big)?serial)/i
    ) {
      $sth->bind_param($bind++, $record->{$field}, { TYPE => SQL_INTEGER } );
    } else {
      $sth->bind_param($bind++, $record->{$field}, { TYPE => SQL_VARCHAR } );
    }
  }

#  $sth->execute( map $record->{$_},
#    grep defined( $record->{$_} ) && $record->{$_} ne '', @fields
#  ) or croak "Error executing \"$statement\": ". $sth->errstr;

  $sth->execute or croak "Error executing \"$statement\": ". $sth->errstr;

  if ( eval 'scalar(@FS::'. $table. '::ISA);' ) {
    @virtual_fields = "FS::$table"->virtual_fields;
  } else {
    cluck "warning: FS::$table not loaded; virtual fields not returned either";
    @virtual_fields = ();
  }

  my %result;
  tie %result, "Tie::IxHash";
  my @stuff = @{ $sth->fetchall_arrayref( {} ) };
  if ( $pkey && scalar(@stuff) && $stuff[0]->{$pkey} ) {
    %result = map { $_->{$pkey}, $_ } @stuff;
  } else {
    @result{@stuff} = @stuff;
  }

  $sth->finish;

  if ( keys(%result) and @virtual_fields ) {
    $statement =
      "SELECT virtual_field.recnum, part_virtual_field.name, ".
             "virtual_field.value ".
      "FROM part_virtual_field JOIN virtual_field USING (vfieldpart) ".
      "WHERE part_virtual_field.dbtable = '$table' AND ".
      "virtual_field.recnum IN (".
      join(',', keys(%result)). ") AND part_virtual_field.name IN ('".
      join(q!', '!, @virtual_fields) . "')";
    warn "[debug]$me $statement\n" if $DEBUG > 1;
    $sth = $dbh->prepare($statement) or croak "$dbh->errstr doing $statement";
    $sth->execute or croak "Error executing \"$statement\": ". $sth->errstr;

    foreach (@{ $sth->fetchall_arrayref({}) }) {
      my $recnum = $_->{recnum};
      my $name = $_->{name};
      my $value = $_->{value};
      if (exists($result{$recnum})) {
        $result{$recnum}->{$name} = $value;
      }
    }
  }
  my @return;
  if ( eval 'scalar(@FS::'. $table. '::ISA);' ) {
    if ( eval 'FS::'. $table. '->can(\'new\')' eq \&new ) {
      #derivied class didn't override new method, so this optimization is safe
      if ( $cache ) {
        @return = map {
          new_or_cached( "FS::$table", { %{$_} }, $cache )
        } values(%result);
      } else {
        @return = map {
          new( "FS::$table", { %{$_} } )
        } values(%result);
      }
    } else {
      #okay, its been tested
      # warn "untested code (class FS::$table uses custom new method)";
      @return = map {
        eval 'FS::'. $table. '->new( { %{$_} } )';
      } values(%result);
    }

    # Check for encrypted fields and decrypt them.
   ## only in the local copy, not the cached object
    if ( $conf && $conf->exists('encryption') # $conf doesn't exist when doing
                                              # the initial search for
                                              # access_user
         && eval 'defined(@FS::'. $table . '::encrypted_fields)') {
      foreach my $record (@return) {
        foreach my $field (eval '@FS::'. $table . '::encrypted_fields') {
          # Set it directly... This may cause a problem in the future...
          $record->setfield($field, $record->decrypt($record->getfield($field)));
        }
      }
    }
  } else {
    cluck "warning: FS::$table not loaded; returning FS::Record objects";
    @return = map {
      FS::Record->new( $table, { %{$_} } );
    } values(%result);
  }
  return @return;
}

=item by_key PRIMARY_KEY_VALUE

This is a class method that returns the record with the given primary key
value.  This method is only useful in FS::Record subclasses.  For example:

  my $cust_main = FS::cust_main->by_key(1); # retrieve customer with custnum 1

is equivalent to:

  my $cust_main = qsearchs('cust_main', { 'custnum' => 1 } );

=cut

sub by_key {
  my ($class, $pkey_value) = @_;

  my $table = $class->table
    or croak "No table for $class found";

  my $dbdef_table = dbdef->table($table)
    or die "No schema for table $table found - ".
           "do you need to create it or run dbdef-create?";
  my $pkey = $dbdef_table->primary_key
    or die "No primary key for table $table";

  return qsearchs($table, { $pkey => $pkey_value });
}

=item jsearch TABLE, HASHREF, SELECT, EXTRA_SQL, PRIMARY_TABLE, PRIMARY_KEY

Experimental JOINed search method.  Using this method, you can execute a
single SELECT spanning multiple tables, and cache the results for subsequent
method calls.  Interface will almost definately change in an incompatible
fashion.

Arguments: 

=cut

sub jsearch {
  my($table, $record, $select, $extra_sql, $ptable, $pkey ) = @_;
  my $cache = FS::SearchCache->new( $ptable, $pkey );
  my %saw;
  ( $cache,
    grep { !$saw{$_->getfield($pkey)}++ }
      qsearch($table, $record, $select, $extra_sql, $cache )
  );
}

=item qsearchs PARAMS_HASHREF | TABLE, HASHREF, SELECT, EXTRA_SQL, CACHE_OBJ, ADDL_FROM

Same as qsearch, except that if more than one record matches, it B<carp>s but
returns the first.  If this happens, you either made a logic error in asking
for a single item, or your data is corrupted.

=cut

sub qsearchs { # $result_record = &FS::Record:qsearchs('table',\%hash);
  my $table = $_[0];
  my(@result) = qsearch(@_);
  cluck "warning: Multiple records in scalar search ($table)"
    if scalar(@result) > 1;
  #should warn more vehemently if the search was on a primary key?
  scalar(@result) ? ($result[0]) : ();
}

=back

=head1 METHODS

=over 4

=item table

Returns the table name.

=cut

sub table {
#  cluck "warning: FS::Record::table deprecated; supply one in subclass!";
  my $self = shift;
  $self -> {'Table'};
}

=item dbdef_table

Returns the DBIx::DBSchema::Table object for the table.

=cut

sub dbdef_table {
  my($self)=@_;
  my($table)=$self->table;
  dbdef->table($table);
}

=item primary_key

Returns the primary key for the table.

=cut

sub primary_key {
  my $self = shift;
  my $pkey = $self->dbdef_table->primary_key;
}

=item get, getfield COLUMN

Returns the value of the column/field/key COLUMN.

=cut

sub get {
  my($self,$field) = @_;
  # to avoid "Use of unitialized value" errors
  if ( defined ( $self->{Hash}->{$field} ) ) {
    $self->{Hash}->{$field};
  } else { 
    '';
  }
}
sub getfield {
  my $self = shift;
  $self->get(@_);
}

=item set, setfield COLUMN, VALUE

Sets the value of the column/field/key COLUMN to VALUE.  Returns VALUE.

=cut

sub set { 
  my($self,$field,$value) = @_;
  $self->{'modified'} = 1;
  $self->{'Hash'}->{$field} = $value;
}
sub setfield {
  my $self = shift;
  $self->set(@_);
}

=item AUTLOADED METHODS

$record->column is a synonym for $record->get('column');

$record->column('value') is a synonym for $record->set('column','value');

=cut

# readable/safe
sub AUTOLOAD {
  my($self,$value)=@_;
  my($field)=$AUTOLOAD;
  $field =~ s/.*://;
  if ( defined($value) ) {
    confess "errant AUTOLOAD $field for $self (arg $value)"
      unless ref($self) && $self->can('setfield');
    $self->setfield($field,$value);
  } else {
    confess "errant AUTOLOAD $field for $self (no args)"
      unless ref($self) && $self->can('getfield');
    $self->getfield($field);
  }    
}

# efficient
#sub AUTOLOAD {
#  my $field = $AUTOLOAD;
#  $field =~ s/.*://;
#  if ( defined($_[1]) ) {
#    $_[0]->setfield($field, $_[1]);
#  } else {
#    $_[0]->getfield($field);
#  }    
#}

=item hash

Returns a list of the column/value pairs, usually for assigning to a new hash.

To make a distinct duplicate of an FS::Record object, you can do:

    $new = new FS::Record ( $old->table, { $old->hash } );

=cut

sub hash {
  my($self) = @_;
  confess $self. ' -> hash: Hash attribute is undefined'
    unless defined($self->{'Hash'});
  %{ $self->{'Hash'} }; 
}

=item hashref

Returns a reference to the column/value hash.  This may be deprecated in the
future; if there's a reason you can't just use the autoloaded or get/set
methods, speak up.

=cut

sub hashref {
  my($self) = @_;
  $self->{'Hash'};
}

=item modified

Returns true if any of this object's values have been modified with set (or via
an autoloaded method).  Doesn't yet recognize when you retreive a hashref and
modify that.

=cut

sub modified {
  my $self = shift;
  $self->{'modified'};
}

=item select_for_update

Selects this record with the SQL "FOR UPDATE" command.  This can be useful as
a mutex.

=cut

sub select_for_update {
  my $self = shift;
  my $primary_key = $self->primary_key;
  qsearchs( {
    'select'    => '*',
    'table'     => $self->table,
    'hashref'   => { $primary_key => $self->$primary_key() },
    'extra_sql' => 'FOR UPDATE',
  } );
}

=item insert

Inserts this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

sub insert {
  my $self = shift;
  my $saved = {};

  warn "$self -> insert" if $DEBUG;

  my $error = $self->check;
  return $error if $error;

  #single-field unique keys are given a value if false
  #(like MySQL's AUTO_INCREMENT or Pg SERIAL)
  foreach ( $self->dbdef_table->can('unique_singles')
              ? $self->dbdef_table->unique_singles
              : $self->dbdef_table->unique->singles
          ) {
    $self->unique($_) unless $self->getfield($_);
  }

  #and also the primary key, if the database isn't going to
  my $primary_key = $self->dbdef_table->primary_key;
  my $db_seq = 0;
  if ( $primary_key ) {
    my $col = $self->dbdef_table->column($primary_key);
    
    $db_seq =
      uc($col->type) =~ /^(BIG)?SERIAL\d?/
      || ( driver_name eq 'Pg'
             && defined($col->default)
             && $col->default =~ /^nextval\(/i
         )
      || ( driver_name eq 'mysql'
             && defined($col->local)
             && $col->local =~ /AUTO_INCREMENT/i
         );
    $self->unique($primary_key) unless $self->getfield($primary_key) || $db_seq;
  }

  my $table = $self->table;

  
  # Encrypt before the database
  if ($conf->exists('encryption') && defined(eval '@FS::'. $table . '::encrypted_fields')) {
    foreach my $field (eval '@FS::'. $table . '::encrypted_fields') {
      $self->{'saved'} = $self->getfield($field);
      $self->setfield($field, $self->encrypt($self->getfield($field)));
    }
  }


  #false laziness w/delete
  my @real_fields =
    grep { defined($self->getfield($_)) && $self->getfield($_) ne "" }
    real_fields($table)
  ;
  my @values = map { _quote( $self->getfield($_), $table, $_) } @real_fields;
  #eslaf

  my $statement = "INSERT INTO $table ";
  if ( @real_fields ) {
    $statement .=
      "( ".
        join( ', ', @real_fields ).
      ") VALUES (".
        join( ', ', @values ).
       ")"
    ;
  } else {
    $statement .= 'DEFAULT VALUES';
  }
  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = dbh->prepare($statement) or return dbh->errstr;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE'; 
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  $sth->execute or return $sth->errstr;

  # get inserted id from the database, if applicable & needed
  if ( $db_seq && ! $self->getfield($primary_key) ) {
    warn "[debug]$me retreiving sequence from database\n" if $DEBUG;
  
    my $insertid = '';

    if ( driver_name eq 'Pg' ) {

      #my $oid = $sth->{'pg_oid_status'};
      #my $i_sql = "SELECT $primary_key FROM $table WHERE oid = ?";

      my $default = $self->dbdef_table->column($primary_key)->default;
      unless ( $default =~ /^nextval\(\(?'"?([\w\.]+)"?'/i ) {
        dbh->rollback if $FS::UID::AutoCommit;
        return "can't parse $table.$primary_key default value".
               " for sequence name: $default";
      }
      my $sequence = $1;

      my $i_sql = "SELECT currval('$sequence')";
      my $i_sth = dbh->prepare($i_sql) or do {
        dbh->rollback if $FS::UID::AutoCommit;
        return dbh->errstr;
      };
      $i_sth->execute() or do { #$i_sth->execute($oid)
        dbh->rollback if $FS::UID::AutoCommit;
        return $i_sth->errstr;
      };
      $insertid = $i_sth->fetchrow_arrayref->[0];

    } elsif ( driver_name eq 'mysql' ) {

      $insertid = dbh->{'mysql_insertid'};
      # work around mysql_insertid being null some of the time, ala RT :/
      unless ( $insertid ) {
        warn "WARNING: DBD::mysql didn't return mysql_insertid; ".
             "using SELECT LAST_INSERT_ID();";
        my $i_sql = "SELECT LAST_INSERT_ID()";
        my $i_sth = dbh->prepare($i_sql) or do {
          dbh->rollback if $FS::UID::AutoCommit;
          return dbh->errstr;
        };
        $i_sth->execute or do {
          dbh->rollback if $FS::UID::AutoCommit;
          return $i_sth->errstr;
        };
        $insertid = $i_sth->fetchrow_arrayref->[0];
      }

    } else {

      dbh->rollback if $FS::UID::AutoCommit;
      return "don't know how to retreive inserted ids from ". driver_name. 
             ", try using counterfiles (maybe run dbdef-create?)";

    }

    $self->setfield($primary_key, $insertid);

  }

  my @virtual_fields = 
      grep defined($self->getfield($_)) && $self->getfield($_) ne "",
          $self->virtual_fields;
  if (@virtual_fields) {
    my %v_values = map { $_, $self->getfield($_) } @virtual_fields;

    my $vfieldpart = $self->vfieldpart_hashref;

    my $v_statement = "INSERT INTO virtual_field(recnum, vfieldpart, value) ".
                    "VALUES (?, ?, ?)";

    my $v_sth = dbh->prepare($v_statement) or do {
      dbh->rollback if $FS::UID::AutoCommit;
      return dbh->errstr;
    };

    foreach (keys(%v_values)) {
      $v_sth->execute($self->getfield($primary_key),
                      $vfieldpart->{$_},
                      $v_values{$_})
      or do {
        dbh->rollback if $FS::UID::AutoCommit;
        return $v_sth->errstr;
      };
    }
  }


  my $h_sth;
  if ( defined dbdef->table('h_'. $table) ) {
    my $h_statement = $self->_h_statement('insert');
    warn "[debug]$me $h_statement\n" if $DEBUG > 2;
    $h_sth = dbh->prepare($h_statement) or do {
      dbh->rollback if $FS::UID::AutoCommit;
      return dbh->errstr;
    };
  } else {
    $h_sth = '';
  }
  $h_sth->execute or return $h_sth->errstr if $h_sth;

  dbh->commit or croak dbh->errstr if $FS::UID::AutoCommit;

  # Now that it has been saved, reset the encrypted fields so that $new 
  # can still be used.
  foreach my $field (keys %{$saved}) {
    $self->setfield($field, $saved->{$field});
  }

  '';
}

=item add

Depriciated (use insert instead).

=cut

sub add {
  cluck "warning: FS::Record::add deprecated!";
  insert @_; #call method in this scope
}

=item delete

Delete this record from the database.  If there is an error, returns the error,
otherwise returns false.

=cut

sub delete {
  my $self = shift;

  my $statement = "DELETE FROM ". $self->table. " WHERE ". join(' AND ',
    map {
      $self->getfield($_) eq ''
        #? "( $_ IS NULL OR $_ = \"\" )"
        ? ( driver_name eq 'Pg'
              ? "$_ IS NULL"
              : "( $_ IS NULL OR $_ = \"\" )"
          )
        : "$_ = ". _quote($self->getfield($_),$self->table,$_)
    } ( $self->dbdef_table->primary_key )
          ? ( $self->dbdef_table->primary_key)
          : real_fields($self->table)
  );
  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = dbh->prepare($statement) or return dbh->errstr;

  my $h_sth;
  if ( defined dbdef->table('h_'. $self->table) ) {
    my $h_statement = $self->_h_statement('delete');
    warn "[debug]$me $h_statement\n" if $DEBUG > 2;
    $h_sth = dbh->prepare($h_statement) or return dbh->errstr;
  } else {
    $h_sth = '';
  }

  my $primary_key = $self->dbdef_table->primary_key;
  my $v_sth;
  my @del_vfields;
  my $vfp = $self->vfieldpart_hashref;
  foreach($self->virtual_fields) {
    next if $self->getfield($_) eq '';
    unless(@del_vfields) {
      my $st = "DELETE FROM virtual_field WHERE recnum = ? AND vfieldpart = ?";
      $v_sth = dbh->prepare($st) or return dbh->errstr;
    }
    push @del_vfields, $_;
  }

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE'; 
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $rc = $sth->execute or return $sth->errstr;
  #not portable #return "Record not found, statement:\n$statement" if $rc eq "0E0";
  $h_sth->execute or return $h_sth->errstr if $h_sth;
  $v_sth->execute($self->getfield($primary_key), $vfp->{$_}) 
    or return $v_sth->errstr 
        foreach (@del_vfields);
  
  dbh->commit or croak dbh->errstr if $FS::UID::AutoCommit;

  #no need to needlessly destoy the data either (causes problems actually)
  #undef $self; #no need to keep object!

  '';
}

=item del

Depriciated (use delete instead).

=cut

sub del {
  cluck "warning: FS::Record::del deprecated!";
  &delete(@_); #call method in this scope
}

=item replace OLD_RECORD

Replace the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

sub replace {
  my ($new, $old) = (shift, shift);

  $old = $new->replace_old unless defined($old);

  warn "[debug]$me $new ->replace $old\n" if $DEBUG;

  if ( $new->can('replace_check') ) {
    my $error = $new->replace_check($old);
    return $error if $error;
  }

  return "Records not in same table!" unless $new->table eq $old->table;

  my $primary_key = $old->dbdef_table->primary_key;
  return "Can't change primary key $primary_key ".
         'from '. $old->getfield($primary_key).
         ' to ' . $new->getfield($primary_key)
    if $primary_key
       && ( $old->getfield($primary_key) ne $new->getfield($primary_key) );

  my $error = $new->check;
  return $error if $error;
  
  # Encrypt for replace
  my $conf = new FS::Conf;
  my $saved = {};
  if ($conf->exists('encryption') && defined(eval '@FS::'. $new->table . '::encrypted_fields')) {
    foreach my $field (eval '@FS::'. $new->table . '::encrypted_fields') {
      $saved->{$field} = $new->getfield($field);
      $new->setfield($field, $new->encrypt($new->getfield($field)));
    }
  }

  #my @diff = grep $new->getfield($_) ne $old->getfield($_), $old->fields;
  my %diff = map { ($new->getfield($_) ne $old->getfield($_))
                   ? ($_, $new->getfield($_)) : () } $old->fields;
                   
  unless (keys(%diff) || $no_update_diff ) {
    carp "[warning]$me $new -> replace $old: records identical"
      unless $nowarn_identical;
    return '';
  }

  my $statement = "UPDATE ". $old->table. " SET ". join(', ',
    map {
      "$_ = ". _quote($new->getfield($_),$old->table,$_) 
    } real_fields($old->table)
  ). ' WHERE '.
    join(' AND ',
      map {

        if ( $old->getfield($_) eq '' ) {

         #false laziness w/qsearch
         if ( driver_name eq 'Pg' ) {
            my $type = $old->dbdef_table->column($_)->type;
            if ( $type =~ /(int|(big)?serial)/i ) {
              qq-( $_ IS NULL )-;
            } else {
              qq-( $_ IS NULL OR $_ = '' )-;
            }
          } else {
            qq-( $_ IS NULL OR $_ = "" )-;
          }

        } else {
          "$_ = ". _quote($old->getfield($_),$old->table,$_);
        }

      } ( $primary_key ? ( $primary_key ) : real_fields($old->table) )
    )
  ;
  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = dbh->prepare($statement) or return dbh->errstr;

  my $h_old_sth;
  if ( defined dbdef->table('h_'. $old->table) ) {
    my $h_old_statement = $old->_h_statement('replace_old');
    warn "[debug]$me $h_old_statement\n" if $DEBUG > 2;
    $h_old_sth = dbh->prepare($h_old_statement) or return dbh->errstr;
  } else {
    $h_old_sth = '';
  }

  my $h_new_sth;
  if ( defined dbdef->table('h_'. $new->table) ) {
    my $h_new_statement = $new->_h_statement('replace_new');
    warn "[debug]$me $h_new_statement\n" if $DEBUG > 2;
    $h_new_sth = dbh->prepare($h_new_statement) or return dbh->errstr;
  } else {
    $h_new_sth = '';
  }

  # For virtual fields we have three cases with different SQL 
  # statements: add, replace, delete
  my $v_add_sth;
  my $v_rep_sth;
  my $v_del_sth;
  my (@add_vfields, @rep_vfields, @del_vfields);
  my $vfp = $old->vfieldpart_hashref;
  foreach(grep { exists($diff{$_}) } $new->virtual_fields) {
    if($diff{$_} eq '') {
      # Delete
      unless(@del_vfields) {
        my $st = "DELETE FROM virtual_field WHERE recnum = ? ".
                 "AND vfieldpart = ?";
        warn "[debug]$me $st\n" if $DEBUG > 2;
        $v_del_sth = dbh->prepare($st) or return dbh->errstr;
      }
      push @del_vfields, $_;
    } elsif($old->getfield($_) eq '') {
      # Add
      unless(@add_vfields) {
        my $st = "INSERT INTO virtual_field (value, recnum, vfieldpart) ".
	         "VALUES (?, ?, ?)";
        warn "[debug]$me $st\n" if $DEBUG > 2;
        $v_add_sth = dbh->prepare($st) or return dbh->errstr;
      }
      push @add_vfields, $_;
    } else {
      # Replace
      unless(@rep_vfields) {
        my $st = "UPDATE virtual_field SET value = ? ".
                 "WHERE recnum = ? AND vfieldpart = ?";
        warn "[debug]$me $st\n" if $DEBUG > 2;
        $v_rep_sth = dbh->prepare($st) or return dbh->errstr;
      }
      push @rep_vfields, $_;
    }
  }

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE'; 
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $rc = $sth->execute or return $sth->errstr;
  #not portable #return "Record not found (or records identical)." if $rc eq "0E0";
  $h_old_sth->execute or return $h_old_sth->errstr if $h_old_sth;
  $h_new_sth->execute or return $h_new_sth->errstr if $h_new_sth;

  $v_del_sth->execute($old->getfield($primary_key),
                      $vfp->{$_})
        or return $v_del_sth->errstr
      foreach(@del_vfields);

  $v_add_sth->execute($new->getfield($_),
                      $old->getfield($primary_key),
                      $vfp->{$_})
        or return $v_add_sth->errstr
      foreach(@add_vfields);

  $v_rep_sth->execute($new->getfield($_),
                      $old->getfield($primary_key),
                      $vfp->{$_})
        or return $v_rep_sth->errstr
      foreach(@rep_vfields);

  dbh->commit or croak dbh->errstr if $FS::UID::AutoCommit;

  # Now that it has been saved, reset the encrypted fields so that $new 
  # can still be used.
  foreach my $field (keys %{$saved}) {
    $new->setfield($field, $saved->{$field});
  }

  '';

}

sub replace_old {
  my( $self ) = shift;
  warn "[$me] replace called with no arguments; autoloading old record\n"
    if $DEBUG;

  my $primary_key = $self->dbdef_table->primary_key;
  if ( $primary_key ) {
    $self->by_key( $self->$primary_key() ) #this is what's returned
      or croak "can't find ". $self->table. ".$primary_key ".
        $self->$primary_key();
  } else {
    croak $self->table. " has no primary key; pass old record as argument";
  }

}

=item rep

Depriciated (use replace instead).

=cut

sub rep {
  cluck "warning: FS::Record::rep deprecated!";
  replace @_; #call method in this scope
}

=item check

Checks virtual fields (using check_blocks).  Subclasses should still provide 
a check method to validate real fields, foreign keys, etc., and call this 
method via $self->SUPER::check.

(FIXME: Should this method try to make sure that it I<is> being called from 
a subclass's check method, to keep the current semantics as far as possible?)

=cut

sub check {
  #confess "FS::Record::check not implemented; supply one in subclass!";
  my $self = shift;

  foreach my $field ($self->virtual_fields) {
    for ($self->getfield($field)) {
      # See notes on check_block in FS::part_virtual_field.
      eval $self->pvf($field)->check_block;
      if ( $@ ) {
        #this is bad, probably want to follow the stack backtrace up and see
        #wtf happened
        my $err = "Fatal error checking $field for $self";
        cluck "$err: $@";
        return "$err (see log for backtrace): $@";

      }
      $self->setfield($field, $_);
    }
  }
  '';
}

sub _h_statement {
  my( $self, $action, $time ) = @_;

  $time ||= time;

  my @fields =
    grep { defined($self->getfield($_)) && $self->getfield($_) ne "" }
    real_fields($self->table);
  ;

  # If we're encrypting then don't ever store the payinfo or CVV2 in the history....
  # You can see if it changed by the paymask...
  if ($conf->exists('encryption') ) {
    @fields = grep  $_ ne 'payinfo' && $_ ne 'cvv2', @fields;
  }
  my @values = map { _quote( $self->getfield($_), $self->table, $_) } @fields;

  "INSERT INTO h_". $self->table. " ( ".
      join(', ', qw(history_date history_user history_action), @fields ).
    ") VALUES (".
      join(', ', $time, dbh->quote(getotaker()), dbh->quote($action), @values).
    ")"
  ;
}

=item unique COLUMN

B<Warning>: External use is B<deprecated>.  

Replaces COLUMN in record with a unique number, using counters in the
filesystem.  Used by the B<insert> method on single-field unique columns
(see L<DBIx::DBSchema::Table>) and also as a fallback for primary keys
that aren't SERIAL (Pg) or AUTO_INCREMENT (mysql).

Returns the new value.

=cut

sub unique {
  my($self,$field) = @_;
  my($table)=$self->table;

  croak "Unique called on field $field, but it is ",
        $self->getfield($field),
        ", not null!"
    if $self->getfield($field);

  #warn "table $table is tainted" if is_tainted($table);
  #warn "field $field is tainted" if is_tainted($field);

  my($counter) = new File::CounterFile "$table.$field",0;
# hack for web demo
#  getotaker() =~ /^([\w\-]{1,16})$/ or die "Illegal CGI REMOTE_USER!";
#  my($user)=$1;
#  my($counter) = new File::CounterFile "$user/$table.$field",0;
# endhack

  my $index = $counter->inc;
  $index = $counter->inc while qsearchs($table, { $field=>$index } );

  $index =~ /^(\d*)$/;
  $index=$1;

  $self->setfield($field,$index);

}

=item ut_float COLUMN

Check/untaint floating point numeric data: 1.1, 1, 1.1e10, 1e10.  May not be
null.  If there is an error, returns the error, otherwise returns false.

=cut

sub ut_float {
  my($self,$field)=@_ ;
  ($self->getfield($field) =~ /^(\d+\.\d+)$/ ||
   $self->getfield($field) =~ /^(\d+)$/ ||
   $self->getfield($field) =~ /^(\d+\.\d+e\d+)$/ ||
   $self->getfield($field) =~ /^(\d+e\d+)$/)
    or return "Illegal or empty (float) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}
=item ut_floatn COLUMN

Check/untaint floating point numeric data: 1.1, 1, 1.1e10, 1e10.  May be
null.  If there is an error, returns the error, otherwise returns false.

=cut

#false laziness w/ut_ipn
sub ut_floatn {
  my( $self, $field ) = @_;
  if ( $self->getfield($field) =~ /^()$/ ) {
    $self->setfield($field,'');
    '';
  } else {
    $self->ut_float($field);
  }
}

=item ut_snumber COLUMN

Check/untaint signed numeric data (whole numbers).  If there is an error,
returns the error, otherwise returns false.

=cut

sub ut_snumber {
  my($self, $field) = @_;
  $self->getfield($field) =~ /^(-?)\s*(\d+)$/
    or return "Illegal or empty (numeric) $field: ". $self->getfield($field);
  $self->setfield($field, "$1$2");
  '';
}

=item ut_snumbern COLUMN

Check/untaint signed numeric data (whole numbers).  If there is an error,
returns the error, otherwise returns false.

=cut

sub ut_snumbern {
  my($self, $field) = @_;
  $self->getfield($field) =~ /^(-?)\s*(\d*)$/
    or return "Illegal (numeric) $field: ". $self->getfield($field);
  if ($1) {
    return "Illegal (numeric) $field: ". $self->getfield($field)
      unless $2;
  }
  $self->setfield($field, "$1$2");
  '';
}

=item ut_number COLUMN

Check/untaint simple numeric data (whole numbers).  May not be null.  If there
is an error, returns the error, otherwise returns false.

=cut

sub ut_number {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\d+)$/
    or return "Illegal or empty (numeric) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_numbern COLUMN

Check/untaint simple numeric data (whole numbers).  May be null.  If there is
an error, returns the error, otherwise returns false.

=cut

sub ut_numbern {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\d*)$/
    or return "Illegal (numeric) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_money COLUMN

Check/untaint monetary numbers.  May be negative.  Set to 0 if null.  If there
is an error, returns the error, otherwise returns false.

=cut

sub ut_money {
  my($self,$field)=@_;
  $self->setfield($field, 0) if $self->getfield($field) eq '';
  $self->getfield($field) =~ /^(\-)? ?(\d*)(\.\d{2})?$/
    or return "Illegal (money) $field: ". $self->getfield($field);
  #$self->setfield($field, "$1$2$3" || 0);
  $self->setfield($field, ( ($1||''). ($2||''). ($3||'') ) || 0);
  '';
}

=item ut_text COLUMN

Check/untaint text.  Alphanumerics, spaces, and the following punctuation
symbols are currently permitted: ! @ # $ % & ( ) - + ; : ' " , . ? / = [ ]
May not be null.  If there is an error, returns the error, otherwise returns
false.

=cut

sub ut_text {
  my($self,$field)=@_;
  #warn "msgcat ". \&msgcat. "\n";
  #warn "notexist ". \&notexist. "\n";
  #warn "AUTOLOAD ". \&AUTOLOAD. "\n";
  $self->getfield($field)
    =~ /^([\w \!\@\#\$\%\&\(\)\-\+\;\:\'\"\,\.\?\/\=\[\]]+)$/
      or return gettext('illegal_or_empty_text'). " $field: ".
                 $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_textn COLUMN

Check/untaint text.  Alphanumerics, spaces, and the following punctuation
symbols are currently permitted: ! @ # $ % & ( ) - + ; : ' " , . ? /
May be null.  If there is an error, returns the error, otherwise returns false.

=cut

sub ut_textn {
  my($self,$field)=@_;
  $self->getfield($field)
    =~ /^([\w \!\@\#\$\%\&\(\)\-\+\;\:\'\"\,\.\?\/\=\[\]]*)$/
      or return gettext('illegal_text'). " $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_alpha COLUMN

Check/untaint alphanumeric strings (no spaces).  May not be null.  If there is
an error, returns the error, otherwise returns false.

=cut

sub ut_alpha {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\w+)$/
    or return "Illegal or empty (alphanumeric) $field: ".
              $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_alpha COLUMN

Check/untaint alphanumeric strings (no spaces).  May be null.  If there is an
error, returns the error, otherwise returns false.

=cut

sub ut_alphan {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\w*)$/ 
    or return "Illegal (alphanumeric) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_phonen COLUMN [ COUNTRY ]

Check/untaint phone numbers.  May be null.  If there is an error, returns
the error, otherwise returns false.

Takes an optional two-letter ISO country code; without it or with unsupported
countries, ut_phonen simply calls ut_alphan.

=cut

sub ut_phonen {
  my( $self, $field, $country ) = @_;
  return $self->ut_alphan($field) unless defined $country;
  my $phonen = $self->getfield($field);
  if ( $phonen eq '' ) {
    $self->setfield($field,'');
  } elsif ( $country eq 'US' || $country eq 'CA' ) {
    $phonen =~ s/\D//g;
    $phonen =~ /^(\d{3})(\d{3})(\d{4})(\d*)$/
      or return gettext('illegal_phone'). " $field: ". $self->getfield($field);
    $phonen = "$1-$2-$3";
    $phonen .= " x$4" if $4;
    $self->setfield($field,$phonen);
  } else {
    warn "warning: don't know how to check phone numbers for country $country";
    return $self->ut_textn($field);
  }
  '';
}

=item ut_hex COLUMN

Check/untaint hexadecimal values.

=cut

sub ut_hex {
  my($self, $field) = @_;
  $self->getfield($field) =~ /^([\da-fA-F]+)$/
    or return "Illegal (hex) $field: ". $self->getfield($field);
  $self->setfield($field, uc($1));
  '';
}

=item ut_hexn COLUMN

Check/untaint hexadecimal values.  May be null.

=cut

sub ut_hexn {
  my($self, $field) = @_;
  $self->getfield($field) =~ /^([\da-fA-F]*)$/
    or return "Illegal (hex) $field: ". $self->getfield($field);
  $self->setfield($field, uc($1));
  '';
}
=item ut_ip COLUMN

Check/untaint ip addresses.  IPv4 only for now.

=cut

sub ut_ip {
  my( $self, $field ) = @_;
  $self->getfield($field) =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
    or return "Illegal (IP address) $field: ". $self->getfield($field);
  for ( $1, $2, $3, $4 ) { return "Illegal (IP address) $field" if $_ > 255; }
  $self->setfield($field, "$1.$2.$3.$4");
  '';
}

=item ut_ipn COLUMN

Check/untaint ip addresses.  IPv4 only for now.  May be null.

=cut

sub ut_ipn {
  my( $self, $field ) = @_;
  if ( $self->getfield($field) =~ /^()$/ ) {
    $self->setfield($field,'');
    '';
  } else {
    $self->ut_ip($field);
  }
}

=item ut_coord COLUMN [ LOWER [ UPPER ] ]

Check/untaint coordinates.
Accepts the following forms:
DDD.DDDDD
-DDD.DDDDD
DDD MM.MMM
-DDD MM.MMM
DDD MM SS
-DDD MM SS
DDD MM MMM
-DDD MM MMM

The "DDD MM SS" and "DDD MM MMM" are potentially ambiguous.
The latter form (that is, the MMM are thousands of minutes) is
assumed if the "MMM" is exactly three digits or two digits > 59.

To be safe, just use the DDD.DDDDD form.

If LOWER or UPPER are specified, then the coordinate is checked
for lower and upper bounds, respectively.

=cut

sub ut_coord {

  my ($self, $field) = (shift, shift);

  my $lower = shift if scalar(@_);
  my $upper = shift if scalar(@_);
  my $coord = $self->getfield($field);
  my $neg = $coord =~ s/^(-)//;

  my ($d, $m, $s) = (0, 0, 0);

  if (
    (($d) = ($coord =~ /^(\s*\d{1,3}(?:\.\d+)?)\s*$/)) ||
    (($d, $m) = ($coord =~ /^(\s*\d{1,3})\s+(\d{1,2}(?:\.\d+))\s*$/)) ||
    (($d, $m, $s) = ($coord =~ /^(\s*\d{1,3})\s+(\d{1,2})\s+(\d{1,3})\s*$/))
  ) {
    $s = (((($s =~ /^\d{3}$/) or $s > 59) ? ($s / 1000) : ($s / 60)) / 60);
    $m = $m / 60;
    if ($m > 59) {
      return "Invalid (coordinate with minutes > 59) $field: "
             . $self->getfield($field);
    }

    $coord = ($neg ? -1 : 1) * sprintf('%.8f', $d + $m + $s);

    if (defined($lower) and ($coord < $lower)) {
      return "Invalid (coordinate < $lower) $field: "
             . $self->getfield($field);;
    }

    if (defined($upper) and ($coord > $upper)) {
      return "Invalid (coordinate > $upper) $field: "
             . $self->getfield($field);;
    }

    $self->setfield($field, $coord);
    return '';
  }

  return "Invalid (coordinate) $field: " . $self->getfield($field);

}

=item ut_coordn COLUMN [ LOWER [ UPPER ] ]

Same as ut_coord, except optionally null.

=cut

sub ut_coordn {

  my ($self, $field) = (shift, shift);

  if ($self->getfield($field) =~ /^$/) {
    return '';
  } else {
    return $self->ut_coord($field, @_);
  }

}


=item ut_domain COLUMN

Check/untaint host and domain names.

=cut

sub ut_domain {
  my( $self, $field ) = @_;
  #$self->getfield($field) =~/^(\w+\.)*\w+$/
  $self->getfield($field) =~/^(([\w\-]+\.)*\w+)$/
    or return "Illegal (domain) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_name COLUMN

Check/untaint proper names; allows alphanumerics, spaces and the following
punctuation: , . - '

May not be null.

=cut

sub ut_name {
  my( $self, $field ) = @_;
  $self->getfield($field) =~ /^([\w \,\.\-\']+)$/
    or return gettext('illegal_name'). " $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_zip COLUMN

Check/untaint zip codes.

=cut

my @zip_reqd_countries = qw( AU CA US ); #CA, US implicit...

sub ut_zip {
  my( $self, $field, $country ) = @_;

  if ( $country eq 'US' ) {

    $self->getfield($field) =~ /^\s*(\d{5}(\-\d{4})?)\s*$/
      or return gettext('illegal_zip'). " $field for country $country: ".
                $self->getfield($field);
    $self->setfield($field, $1);

  } elsif ( $country eq 'CA' ) {

    $self->getfield($field) =~ /^\s*([A-Z]\d[A-Z])\s*(\d[A-Z]\d)\s*$/i
      or return gettext('illegal_zip'). " $field for country $country: ".
                $self->getfield($field);
    $self->setfield($field, "$1 $2");

  } else {

    if ( $self->getfield($field) =~ /^\s*$/
         && ( !$country || ! grep { $_ eq $country } @zip_reqd_countries )
       )
    {
      $self->setfield($field,'');
    } else {
      $self->getfield($field) =~ /^\s*(\w[\w\-\s]{2,8}\w)\s*$/
        or return gettext('illegal_zip'). " $field: ". $self->getfield($field);
      $self->setfield($field,$1);
    }

  }

  '';
}

=item ut_country COLUMN

Check/untaint country codes.  Country names are changed to codes, if possible -
see L<Locale::Country>.

=cut

sub ut_country {
  my( $self, $field ) = @_;
  unless ( $self->getfield($field) =~ /^(\w\w)$/ ) {
    if ( $self->getfield($field) =~ /^([\w \,\.\(\)\']+)$/ 
         && country2code($1) ) {
      $self->setfield($field,uc(country2code($1)));
    }
  }
  $self->getfield($field) =~ /^(\w\w)$/
    or return "Illegal (country) $field: ". $self->getfield($field);
  $self->setfield($field,uc($1));
  '';
}

=item ut_anything COLUMN

Untaints arbitrary data.  Be careful.

=cut

sub ut_anything {
  my( $self, $field ) = @_;
  $self->getfield($field) =~ /^(.*)$/s
    or return "Illegal $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_enum COLUMN CHOICES_ARRAYREF

Check/untaint a column, supplying all possible choices, like the "enum" type.

=cut

sub ut_enum {
  my( $self, $field, $choices ) = @_;
  foreach my $choice ( @$choices ) {
    if ( $self->getfield($field) eq $choice ) {
      $self->setfield($choice);
      return '';
    }
  }
  return "Illegal (enum) field $field: ". $self->getfield($field);
}

=item ut_foreign_key COLUMN FOREIGN_TABLE FOREIGN_COLUMN

Check/untaint a foreign column key.  Call a regular ut_ method (like ut_number)
on the column first.

=cut

sub ut_foreign_key {
  my( $self, $field, $table, $foreign ) = @_;
  qsearchs($table, { $foreign => $self->getfield($field) })
    or return "Can't find ". $self->table. ".$field ". $self->getfield($field).
              " in $table.$foreign";
  '';
}

=item ut_foreign_keyn COLUMN FOREIGN_TABLE FOREIGN_COLUMN

Like ut_foreign_key, except the null value is also allowed.

=cut

sub ut_foreign_keyn {
  my( $self, $field, $table, $foreign ) = @_;
  $self->getfield($field)
    ? $self->ut_foreign_key($field, $table, $foreign)
    : '';
}

=item ut_agentnum_acl

Checks this column as an agentnum, taking into account the current users's
ACLs.

=cut

sub ut_agentnum_acl {
  my( $self, $field, $null_acl ) = @_;

  my $error = $self->ut_foreign_keyn($field, 'agent', 'agentnum');
  return "Illegal agentnum: $error" if $error;

  my $curuser = $FS::CurrentUser::CurrentUser;

  if ( $self->$field() ) {

    return "Access deined"
      unless $curuser->agentnum($self->$field());

  } else {

    return "Access denied"
      unless $curuser->access_right($null_acl);

  }

  '';

}

=item virtual_fields [ TABLE ]

Returns a list of virtual fields defined for the table.  This should not 
be exported, and should only be called as an instance or class method.

=cut

sub virtual_fields {
  my $self = shift;
  my $table;
  $table = $self->table or confess "virtual_fields called on non-table";

  confess "Unknown table $table" unless dbdef->table($table);

  return () unless dbdef->table('part_virtual_field');

  unless ( $virtual_fields_cache{$table} ) {
    my $query = 'SELECT name from part_virtual_field ' .
                "WHERE dbtable = '$table'";
    my $dbh = dbh;
    my $result = $dbh->selectcol_arrayref($query);
    confess "Error executing virtual fields query: $query: ". $dbh->errstr
      if $dbh->err;
    $virtual_fields_cache{$table} = $result;
  }

  @{$virtual_fields_cache{$table}};

}


=item fields [ TABLE ]

This is a wrapper for real_fields and virtual_fields.  Code that called
fields before should probably continue to call fields.

=cut

sub fields {
  my $something = shift;
  my $table;
  if($something->isa('FS::Record')) {
    $table = $something->table;
  } else {
    $table = $something;
    $something = "FS::$table";
  }
  return (real_fields($table), $something->virtual_fields());
}

=item pvf FIELD_NAME

Returns the FS::part_virtual_field object corresponding to a field in the 
record (specified by FIELD_NAME).

=cut

sub pvf {
  my ($self, $name) = (shift, shift);

  if(grep /^$name$/, $self->virtual_fields) {
    return qsearchs('part_virtual_field', { dbtable => $self->table,
                                            name    => $name } );
  }
  ''
}

=item vfieldpart_hashref TABLE

Returns a hashref of virtual field names and vfieldparts applicable to the given
TABLE.

=cut

sub vfieldpart_hashref {
  my $self = shift;
  my $table = $self->table;

  return {} unless dbdef->table('part_virtual_field');

  my $dbh = dbh;
  my $statement = "SELECT vfieldpart, name FROM part_virtual_field WHERE ".
                  "dbtable = '$table'";
  my $sth = $dbh->prepare($statement);
  $sth->execute or croak "Execution of '$statement' failed: ".$dbh->errstr;
  return { map { $_->{name}, $_->{vfieldpart} } 
    @{$sth->fetchall_arrayref({})} };

}

=item encrypt($value)

Encrypts the credit card using a combination of PK to encrypt and uuencode to armour.

Returns the encrypted string.

You should generally not have to worry about calling this, as the system handles this for you.

=cut

sub encrypt {
  my ($self, $value) = @_;
  my $encrypted;

  my $conf = new FS::Conf;
  if ($conf->exists('encryption')) {
    if ($self->is_encrypted($value)) {
      # Return the original value if it isn't plaintext.
      $encrypted = $value;
    } else {
      $self->loadRSA;
      if (ref($rsa_encrypt) =~ /::RSA/) { # We Can Encrypt
        # RSA doesn't like the empty string so let's pack it up
        # The database doesn't like the RSA data so uuencode it
        my $length = length($value)+1;
        $encrypted = pack("u*",$rsa_encrypt->encrypt(pack("Z$length",$value)));
      } else {
        die ("You can't encrypt w/o a valid RSA engine - Check your installation or disable encryption");
      }
    }
  }
  return $encrypted;
}

=item is_encrypted($value)

Checks to see if the string is encrypted and returns true or false (1/0) to indicate it's status.

=cut


sub is_encrypted {
  my ($self, $value) = @_;
  # Possible Bug - Some work may be required here....

  if ($value =~ /^M/ && length($value) > 80) {
    return 1;
  } else {
    return 0;
  }
}

=item decrypt($value)

Uses the private key to decrypt the string. Returns the decryoted string or undef on failure.

You should generally not have to worry about calling this, as the system handles this for you.

=cut

sub decrypt {
  my ($self,$value) = @_;
  my $decrypted = $value; # Will return the original value if it isn't encrypted or can't be decrypted.
  my $conf = new FS::Conf;
  if ($conf->exists('encryption') && $self->is_encrypted($value)) {
    $self->loadRSA;
    if (ref($rsa_decrypt) =~ /::RSA/) {
      my $encrypted = unpack ("u*", $value);
      $decrypted =  unpack("Z*", eval{$rsa_decrypt->decrypt($encrypted)});
      if ($@) {warn "Decryption Failed"};
    }
  }
  return $decrypted;
}

sub loadRSA {
    my $self = shift;
    #Initialize the Module
    $rsa_module = 'Crypt::OpenSSL::RSA'; # The Default

    my $conf = new FS::Conf;
    if ($conf->exists('encryptionmodule') && $conf->config('encryptionmodule') ne '') {
      $rsa_module = $conf->config('encryptionmodule');
    }

    if (!$rsa_loaded) {
	eval ("require $rsa_module"); # No need to import the namespace
	$rsa_loaded++;
    }
    # Initialize Encryption
    if ($conf->exists('encryptionpublickey') && $conf->config('encryptionpublickey') ne '') {
      my $public_key = join("\n",$conf->config('encryptionpublickey'));
      $rsa_encrypt = $rsa_module->new_public_key($public_key);
    }
    
    # Intitalize Decryption
    if ($conf->exists('encryptionprivatekey') && $conf->config('encryptionprivatekey') ne '') {
      my $private_key = join("\n",$conf->config('encryptionprivatekey'));
      $rsa_decrypt = $rsa_module->new_private_key($private_key);
    }
}

=item h_search ACTION

Given an ACTION, either "insert", or "delete", returns the appropriate history
record corresponding to this record, if any.

=cut

sub h_search {
  my( $self, $action ) = @_;

  my $table = $self->table;
  $table =~ s/^h_//;

  my $primary_key = dbdef->table($table)->primary_key;

  qsearchs({
    'table'   => "h_$table",
    'hashref' => { $primary_key     => $self->$primary_key(),
                   'history_action' => $action,
                 },
  });

}

=item h_date ACTION

Given an ACTION, either "insert", or "delete", returns the timestamp of the
appropriate history record corresponding to this record, if any.

=cut

sub h_date {
  my($self, $action) = @_;
  my $h = $self->h_search($action);
  $h ? $h->history_date : '';
}

=back

=head1 SUBROUTINES

=over 4

=item real_fields [ TABLE ]

Returns a list of the real columns in the specified table.  Called only by 
fields() and other subroutines elsewhere in FS::Record.

=cut

sub real_fields {
  my $table = shift;

  my($table_obj) = dbdef->table($table);
  confess "Unknown table $table" unless $table_obj;
  $table_obj->columns;
}

=item _quote VALUE, TABLE, COLUMN

This is an internal function used to construct SQL statements.  It returns
VALUE DBI-quoted (see L<DBI/"quote">) unless VALUE is a number and the column
type (see L<DBIx::DBSchema::Column>) does not end in `char' or `binary'.

=cut

sub _quote {
  my($value, $table, $column) = @_;
  my $column_obj = dbdef->table($table)->column($column);
  my $column_type = $column_obj->type;
  my $nullable = $column_obj->null;

  warn "  $table.$column: $value ($column_type".
       ( $nullable ? ' NULL' : ' NOT NULL' ).
       ")\n" if $DEBUG > 2;

  if ( $value eq '' && $nullable ) {
    'NULL'
  } elsif ( $value eq '' && $column_type =~ /^(int|numeric)/ ) {
    cluck "WARNING: Attempting to set non-null integer $table.$column null; ".
          "using 0 instead";
    0;
  } elsif ( $value =~ /^\d+(\.\d+)?$/ && 
            ! $column_type =~ /(char|binary|text)$/i ) {
    $value;
  } else {
    dbh->quote($value);
  }
}

=item hfields TABLE

This is deprecated.  Don't use it.

It returns a hash-type list with the fields of this record's table set true.

=cut

sub hfields {
  carp "warning: hfields is deprecated";
  my($table)=@_;
  my(%hash);
  foreach (fields($table)) {
    $hash{$_}=1;
  }
  \%hash;
}

sub _dump {
  my($self)=@_;
  join("\n", map {
    "$_: ". $self->getfield($_). "|"
  } (fields($self->table)) );
}

sub DESTROY { return; }

#sub DESTROY {
#  my $self = shift;
#  #use Carp qw(cluck);
#  #cluck "DESTROYING $self";
#  warn "DESTROYING $self";
#}

#sub is_tainted {
#             return ! eval { join('',@_), kill 0; 1; };
#         }

=item str2time_sql [ DRIVER_NAME ]

Returns a function to convert to unix time based on database type, such as
"EXTRACT( EPOCH FROM" for Pg or "UNIX_TIMESTAMP(" for mysql.  You are
responsible for the closing parenthesis yourself.  Don't let it down.  It's a
sensitive parenthesis.

You can pass an optional driver name such as "Pg", "mysql" or
$dbh->{Driver}->{Name} to return a function for that database instead of
the current database.

=cut

sub str2time_sql { 
  my $driver = shift || driver_name;

  return 'UNIX_TIMESTAMP('      if $driver =~ /^mysql/i;
  return 'EXTRACT( EPOCH FROM ' if $driver =~ /^Pg/i;

  warn "warning: unknown database type $driver; guessing how to convert ".
       "dates to UNIX timestamps";
  return 'EXTRACT(EPOCH FROM ';

}

=back

=head1 BUGS

This module should probably be renamed, since much of the functionality is
of general use.  It is not completely unlike Adapter::DBI (see below).

Exported qsearch and qsearchs should be deprecated in favor of method calls
(against an FS::Record object like the old search and searchs that qsearch
and qsearchs were on top of.)

The whole fields / hfields mess should be removed.

The various WHERE clauses should be subroutined.

table string should be deprecated in favor of DBIx::DBSchema::Table.

No doubt we could benefit from a Tied hash.  Documenting how exists / defined
true maps to the database (and WHERE clauses) would also help.

The ut_ methods should ask the dbdef for a default length.

ut_sqltype (like ut_varchar) should all be defined

A fallback check method should be provided which uses the dbdef.

The ut_money method assumes money has two decimal digits.

The Pg money kludge in the new method only strips `$'.

The ut_phonen method only checks US-style phone numbers.

The _quote function should probably use ut_float instead of a regex.

All the subroutines probably should be methods, here or elsewhere.

Probably should borrow/use some dbdef methods where appropriate (like sub
fields)

As of 1.14, DBI fetchall_hashref( {} ) doesn't set fetchrow_hashref NAME_lc,
or allow it to be set.  Working around it is ugly any way around - DBI should
be fixed.  (only affects RDBMS which return uppercase column names)

ut_zip should take an optional country like ut_phone.

=head1 SEE ALSO

L<DBIx::DBSchema>, L<FS::UID>, L<DBI>

Adapter::DBI from Ch. 11 of Advanced Perl Programming by Sriram Srinivasan.

http://poop.sf.net/

=cut

1;

