#!/usr/local/bin/perl -w

use strict;
use Getopt::Long;
use Cwd 'chdir';

$| = 1;

my $usage = "\nUsage: $0 -pass XXXXX input_file

Copy mysql databases between different servers and run myisamchk on the indices when copied.

The input file should have the following format

source_server\tsource_database\tdestination_server\tdestination_database

e.g.

#source_server\\tsource_db\\tdestination_server\\tdestination_db
ecs3d.internal.sanger.ac.uk     homo_sapiens_core_13_31 ecs2d.internal.sanger.ac.uk     homo_sapiens_core_14_31

Lines starting with # are ignored and considered as comments.

RESTRICTIONS:
============
1- The destination_server has to match the generic server you are running the script on,
   either ecs1, ecs2 or ecs3, otherwise the copying process for the corresponding database
   is skipped
2- This script works only for copy processes from and to ecs nodes, namely
   ecs1[abcdefgh]
   ecs2[abcdef]
   ecs3d only
3- -pass is compulsory and is expected to be the mysql password to connect as ensadmin

";

my $help = 0;
my $pass;

GetOptions('h' => \$help,
	   'pass=s' => \$pass);

if ($help || scalar @ARGV == 0 || ! defined $pass) {
  print $usage;
  exit 0;
}

my ($input_file) = @ARGV;
my @dbs_to_copy;

my %mysql_directory_per_svr = ('ecs1a' => "/mysql1a",
			       'ecs1b' => "/mysql2a",
			       'ecs1c' => "/mysql3a",
			       'ecs1d' => "/mysql4a",
			       'ecs1e' => "/mysql5a",
			       'ecs1f' => "/mysql6a",
			       'ecs1g' => "/mysql7a",
			       'ecs1h' => "/mysql_archive",
			       'ecs2a' => "/mysqla",
			       'ecs2b' => "/mysqlb",
			       'ecs2c' => "/mysqlc",
			       'ecs2d' => "/mysqld",
			       'ecs2e' => "/mysqle",
			       'ecs2f' => "/mysqlf",
			       'ecs3d' => "/mysqld");

my $source_port = 3306;
my %mysql_port_per_svr = ('ecs3d' => 3307);
my $working_host = $ENV{'HOST'};
my $generic_working_host = $working_host;
$generic_working_host =~ s/(ecs[123]).*/$1/;
my $working_dir = $ENV{'PWD'};
my $copy_executable = "/usr/bin/cp";
my %already_flushed;

# parsing/checking the input file

open F, $input_file ||
  die "Can not open $input_file, $!\n";

while (my $line = <F>) {
  next if ($line =~ /^\#.*$/);
  if ($line =~ /^(\S+)\t(\S+)\t(\S+)\t(\S+)$/) {
    my ($src_srv,$src_db,$dest_srv,$dest_db) = ($1,$2,$3,$4);
    unless ($dest_srv =~ /^$generic_working_host.*$/) {
      my $generic_destination_server = $dest_srv;
      $generic_destination_server =~ s/(ecs[123]).*/$1/;
      warn "// skipped copy of $src_db from $src_srv to $dest_srv
// this script should be run on a generic destination host $generic_destination_server\n";
      next;
    }
    my $src_srv_ok = 0;
    my $dest_srv_ok = 0;
    foreach my $available_srv (keys %mysql_directory_per_svr) {
      if ($src_srv =~ /^$available_srv.*$/) {
	$src_srv_ok = 1;
      }
      if ($dest_srv =~ /^$available_srv.*$/) {
	$dest_srv_ok = 1;
      }
    }
    unless ($src_srv_ok && $dest_srv) {
      warn "// skipped copy of $src_db from $src_srv to $dest_srv
// this script works only to copy dbs between certain ecs nodes" .
join(", ", keys %mysql_directory_per_svr) ."\n";
      next;
    }
    my %hash = ('src_srv' => $src_srv,
		'src_db' => $src_db,
		'dest_srv' => $dest_srv,
		'dest_db' => $dest_db,
		'status' => "FAILED");
    push @dbs_to_copy, \%hash;
  } else {
    warn "
The input file has the wrong format,
$line
source_server\\tsource_db\\tdestination_server\\tdestination_db
EXIT 1
";
    exit 1;
  }
}

close F;

# starting copy processes
foreach my $db_to_copy (@dbs_to_copy) {
  print STDERR "//
// Starting new copy process
//\n";


  my $source_srv = $db_to_copy->{src_srv};
  $source_srv =~ s/(ecs[123].{1}).*/$1/;
  if (defined $mysql_port_per_svr{$source_srv}) {
    $source_port = $mysql_port_per_svr{$source_srv};
  }
  my $source_db = $mysql_directory_per_svr{$source_srv}."/current/var/".$db_to_copy->{src_db};

  my $destination_srv = $db_to_copy->{dest_srv};
  $destination_srv =~ s/(ecs[123].{1}).*/$1/;
  my $destination_tmp_directory = $mysql_directory_per_svr{$destination_srv}."/current/tmp";
  my $destination_directory = $mysql_directory_per_svr{$destination_srv}."/current/var";

  # checking that destination db does not exist
  if (-e "$destination_directory/$db_to_copy->{dest_db}") {
    print STDERR "// $destination_directory/$db_to_copy->{dest_db} already exists, make sure to
// delete it or use another destination name for the database
// Skipped copy of $db_to_copy->{src_db} from $db_to_copy->{src_srv} to $db_to_copy->{dest_srv}
";
    next;
  }
  
  my $myisamchk_executable = $mysql_directory_per_svr{$destination_srv}."/current/bin/myisamchk";
    
  $source_srv =~ s/(ecs[123]).*/$1/;
  $destination_srv =~ s/(ecs[123]).*/$1/;

  if ($source_srv ne $destination_srv) {
    $copy_executable = "/usr/bin/rcp";
  }

  $source_srv = undef;
  $destination_srv = undef;

  # flush tables; in the source server
  unless (defined $already_flushed{$db_to_copy->{src_srv}}) {
    print STDERR "// flushing tables in $db_to_copy->{src_srv}...";
    my $flush_cmd = "echo \"flush tables;\" | mysql -h $db_to_copy->{src_srv} -u ensadmin -p$pass -P$source_port";
    if (system($flush_cmd) == 0) {
      print STDERR "DONE\n";
    } else {
      print STDERR "FAILED
skipped copy of ".$db_to_copy->{src_db}." from ".$db_to_copy->{src_srv}." to ". $db_to_copy->{dest_srv} . "\n";
      next;
    }
    $already_flushed{$db_to_copy->{src_srv}} = 1;
  }

  # cp the db to $destination_tmp_directory in the destination server
  my $copy_cmd;
  if ($copy_executable eq "/usr/bin/cp") {
    print STDERR "// cp Copying $db_to_copy->{src_srv}:$source_db...";
    $copy_cmd = "$copy_executable -r $source_db $destination_tmp_directory/$db_to_copy->{dest_db}";
    
  # OR rcp the db to $destination_tmp_directory in the destination server
  } elsif ($copy_executable eq "/usr/bin/rcp") {
    print STDERR "// rcp Copying $db_to_copy->{src_srv}:$source_db...";
    $copy_cmd = "$copy_executable -r $db_to_copy->{src_srv}:$source_db $destination_tmp_directory/$db_to_copy->{dest_db}";
  }

  if (system("$copy_cmd") == 0) {
    print STDERR "DONE\n";
  } else {
    print STDERR "FAILED
skipped copy of $db_to_copy->{src_db} from $db_to_copy->{src_srv} to $db_to_copy->{dest_srv}\n";
    next;
  }

  # checks/fixes the indices
  print STDERR "// Checking $destination_tmp_directory/$db_to_copy->{dest_db}/*.MYI in progress...
//\n";
  chdir "$destination_tmp_directory/$db_to_copy->{dest_db}";
  my $myisamchk_cmd = "ls | grep MYI | xargs $myisamchk_executable -r";
  if (system("$myisamchk_cmd") == 0) {
    print STDERR "//
// Checking $destination_tmp_directory/$db_to_copy->{dest_db}/*.MYI DONE\n";
    chdir "$working_dir";
  } else {
    print STDERR "//
// Checking $destination_tmp_directory/$db_to_copy->{dest_db}/*.MYI FAILED
skipped checking/copying of $db_to_copy->{dest_db}\n";
    system("rm -rf $destination_tmp_directory/$db_to_copy->{dest_db}");
    chdir "$working_dir";
    next;
  }

  # moved db to mysql directory if checking went fine, skip otherwise
  if (system("mv $destination_tmp_directory/$db_to_copy->{dest_db} $destination_directory") == 0) {
    print STDERR "// moving $destination_tmp_directory/$db_to_copy->{dest_db} to $destination_directory DONE\n";
  } else {
    print STDERR "// moving $destination_tmp_directory/$db_to_copy->{dest_db} to $destination_directory FAILED\n";
    system("rm -rf $destination_tmp_directory/$db_to_copy->{dest_db}");
    next;
  }
  $db_to_copy->{status} = "SUCCEEDED";
}

print STDERR "//
// End of all copy processes
//
// Processes summary\n";


foreach  my $db_to_copy (@dbs_to_copy) {
  print STDERR "// $db_to_copy->{status} copy of $db_to_copy->{src_db} on $db_to_copy->{src_srv} to $db_to_copy->{dest_db} on $db_to_copy->{dest_srv} \n";
}

print STDERR "\n";
