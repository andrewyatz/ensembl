use strict;

use Bio::EnsEMBL::Test::TestUtils;

use Test::More;

use Bio::EnsEMBL::Test::MultiTestDB;
use Bio::EnsEMBL::Attribute;

our $verbose = 1;
our $clean   = 0;

my $multi = Bio::EnsEMBL::Test::MultiTestDB->new;
my $dbtype = 'patch';
my $dbid = 92975;
my $stable_id = "ENSG00000112761";
my $stable_id2 = "ENSG00000112769";
my $count;

# get a DBAdaptor
my $db = $multi->get_DBAdaptor($dbtype);

my $slice_adaptor = $db->get_SliceAdaptor();
my $mfa           = $db->get_MiscFeatureAdaptor();
my $ga            = $db->get_GeneAdaptor();

#
# Test get_AttributeAdaptor works
#
my $aa = $db->get_AttributeAdaptor();

is(ref($aa), 'Bio::EnsEMBL::DBSQL::AttributeAdaptor', "We have an attribute adaptor");

# hide the contents of the attrib_type, misc_attrib, seq_region_attrib tables
# so we can test storing etc. with a clean slate
$multi->hide($dbtype, 'misc_attrib', 'seq_region_attrib', 'attrib_type', 'gene_attrib');

##############
# MiscFeature functionality tests
#

my $attrib = Bio::EnsEMBL::Attribute->new(-NAME        => 'test_name',
				          -CODE        => 'test_code',
					  -DESCRIPTION => 'test_desc',
					  -VALUE       => 'test_value');

my $mf = $mfa->fetch_by_dbID($dbid);
$aa->store_on_MiscFeature($mf, [$attrib]);

#
# make sure the misc_attrib table was updated
#
is_rows(1, $db, "misc_attrib", "where misc_feature_id = ? ", [$dbid]);

#
# make sure the attrib_type table was updated
#
is_rows(1, $db, "attrib_type", "where code = ? ", ["test_code"]);

#
# test that we can now retrieve this attribute
#
my @attribs = @{$aa->fetch_all_by_MiscFeature($mf)};

is(@attribs, 1, "Fetched 1 features");

$attrib = $attribs[0];

is($attrib->name, 'test_name', "Attrib name is test_name");
is($attrib->code, 'test_code', "Attrib code is test_code");
is($attrib->description, 'test_desc', "Attrib description is test_desc");
is($attrib->value, 'test_value', "Attrib value is test_value");

@attribs = @{$aa->fetch_all_by_MiscFeature()};

is(@attribs, 1, "One attrib fetched");

$attrib = $attribs[0];

is($attrib->name, 'test_name', "Attrib name is test_name");
is($attrib->code, 'test_code', "Attrib code is test_code");
is($attrib->description, 'test_desc', "Attrib description is test_desc");
is($attrib->value, 'test_value', "Attrib value is test_value");

#
# test the removal of this attribute
#
$aa->remove_from_MiscFeature($mf);

#
# make sure the misc_attrib table was updated
#

is_rows(0, $db, "misc_attrib", "where misc_feature_id = ? ", [$dbid]);

#
# make sure the attribute is no longer retrievable
#
@attribs = @{$aa->fetch_all_by_MiscFeature($mf)};
is(@attribs, 0, "Attribute is no longer retrievable");

#################
# Slice functionality tests
#

$attrib = Bio::EnsEMBL::Attribute->new(-NAME        => 'test_name2',
									   -CODE        => 'test_code2',
									   -DESCRIPTION => 'test_desc2',
									   -VALUE       => 'test_value2');

my $slice = $slice_adaptor->fetch_by_region('chromosome', '6');

$aa->store_on_Slice($slice, [$attrib]);
my $seqid = $slice->get_seq_region_id();

#
# make sure the seq_region_attrib table was updated
#

is_rows(1, $db, "seq_region_attrib", "where seq_region_id = ? ", [$seqid]);

#
# make sure the attrib_type table was updated
#
is_rows(1, $db, "attrib_type", "where code = ? ", ["test_code2"]);

#
# test that we can now retrieve this attribute
#
@attribs = @{$aa->fetch_all_by_Slice($slice)};
is(@attribs, 1, "Fetched attribute");

@attribs = @{$aa->fetch_all_by_Slice($slice, "rubbish")};
is(@attribs, 0, "No attribute fetched for code rubbish");

@attribs = @{$aa->fetch_all_by_Slice($slice, "test_code2")};
is(@attribs, 1, "One attribute fetched for test_code2");

@attribs = @{$aa->fetch_all_by_Slice(undef, "test_code2")};
is(@attribs, 1, "One attribute fetched across all slices");

$attrib = $attribs[0];

is($attrib->name, 'test_name2', "Attrib name is test_name2");
is($attrib->code, 'test_code2', "Attrib code is test_code2");
is($attrib->description, 'test_desc2', "Attrib description is test_desc2");
is($attrib->value, 'test_value2', "Attrib value is test_value2");

#
# test the removal of this attribute with attrib code
#
$aa->remove_from_Slice($slice, "junk");

is_rows(1, $db, "seq_region_attrib", "where seq_region_id = ? ", [$seqid]);

#
# test the removal of this attribute
#

$aa->remove_from_Slice($slice, "test_code2");

is_rows(0, $db, "seq_region_attrib", "where seq_region_id = ? ", [$seqid]);

#
# make sure the attribute is no longer retrievable
#
@attribs = @{$aa->fetch_all_by_Slice($slice)};
is(@attribs, 0, "No attribs left for slice");

#
# try to add an attribute with an already existing code
#
$aa->store_on_Slice($slice, [$attrib]);
#
# make sure the seq_region_attrib table was updated
#

is_rows(1, $db, "seq_region_attrib", "where seq_region_id = ? ", [$seqid]);

#
# make sure the attrib_type table was updated
#
is_rows(1, $db, "attrib_type", "where code = ? ", ["test_code2"]);

@attribs = @{$aa->fetch_all_by_Slice($slice)};
is(@attribs, 1, "One attrib on slice");

@attribs = @{$aa->fetch_all_by_Slice(undef)};
is(@attribs, 1, "One attrib for all slices");

#
# test the removal of this attribute
#
$aa->remove_from_Slice($slice);

is_rows(0, $db, "seq_region_attrib", "where seq_region_id = ? " , [$seqid]);

#
# test the storage of empty attrib values
#
{
  my %args = (-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2');
  my $current_rows = count_rows($db, 'seq_region_attrib');
  my $atrib = Bio::EnsEMBL::Attribute->new(%args,);
  $aa->store_on_Slice($slice, [Bio::EnsEMBL::Attribute->new(%args, -VALUE => q{})]);
  $aa->store_on_Slice($slice, [Bio::EnsEMBL::Attribute->new(%args, -VALUE => 0)]);
  my $new_rows = count_rows($db, 'seq_region_attrib');
  cmp_ok($new_rows, '>', $current_rows, 'Asserting the storage of undefined attributes will always store them');
  # now remove again
  $aa->remove_from_Slice($slice);
  $count = $db->dbc->db_handle->selectall_arrayref("SELECT count(*) FROM seq_region_attrib " . "WHERE seq_region_id = " . $slice->get_seq_region_id())->[0]->[0];

  is_rows(0, $db, "seq_region_attrib", "where seq_region_id = ? ", [$seqid]);

}

#################
# Gene functionality tests
#

$attrib = Bio::EnsEMBL::Attribute->new(-NAME        => 'test_name2',
									   -CODE        => 'test_code2',
									   -DESCRIPTION => 'test_desc2',
									   -VALUE       => 'test_value2');

my $gene = $ga->fetch_by_stable_id($stable_id);
my $gene_id = $gene->dbID();

$aa->store_on_Gene($gene, [$attrib]);

#
# make sure the seq_region_attrib table was updated
#
is_rows(1, $db, "gene_attrib", "where gene_id = ? ", [$gene_id]);

#
# make sure the attrib_type table was updated
#
is_rows(1, $db, "attrib_type", "where code = ? ", ["test_code2"]);

#
# test that we can now retrieve this attribute
#
@attribs = @{$aa->fetch_all_by_Gene($gene)};
is(@attribs, 1, "Fetched one attribute for gene");

@attribs = @{$aa->fetch_all_by_Gene($gene, "rubbish")};
is(@attribs, 0, "Fetched no attribute for code rubbish");

@attribs = @{$aa->fetch_all_by_Gene($gene, "test_code2")};
is(@attribs, 1, "Fetched one attribute for code test_code2");

@attribs = @{$aa->fetch_all_by_Gene(undef, "test_code2")};
is(@attribs, 1, "Fetch one attribute for genes");

$attrib = $attribs[0];

is($attrib->name, 'test_name2', "Attrib name is test_name2");
is($attrib->code, 'test_code2', "Attrib code is test_code2");
is($attrib->description, 'test_desc2', "Attrib description is test_desc2");
is($attrib->value, 'test_value2', "Attrib value is test_value2");

#
# test the removal of this attribute with atrrib code
#
$aa->remove_from_Gene($gene, "junk");
is_rows(1, $db, "gene_attrib", "where gene_id = ? ", [$gene_id]);

#
# test the removal of this attribute
#

$aa->remove_from_Gene($gene, "test_code2");
is_rows(0, $db, "gene_attrib", "where gene_id = ? ", [$gene_id]);

#
# make sure the attribute is no longer retrievable
#
@attribs = @{$aa->fetch_all_by_Gene($gene)};
is(@attribs, 0, "No attribs available for gene");

#
# try to add an attribute with an already existing code
#
$aa->store_on_Gene($gene, [$attrib]);
#
# make sure the seq_region_attrib table was updated
#
is_rows(1, $db, "gene_attrib", "where gene_id = ? ", [$gene_id]);

#
# make sure the attrib_type table was updated
#
is_rows(1, $db, "attrib_type", "where code = ? ", ["test_code2"]);

@attribs = @{$aa->fetch_all_by_Gene($gene)};
is(@attribs, 1, "One attrib for gene");

@attribs = @{$aa->fetch_all_by_Gene(undef)};
is(@attribs, 1, "One attrib for genes");

#
# test the removal of this attribute
#
$aa->remove_from_Gene($gene);
is_rows(0, $db, "gene_attrib", "where gene_id = ? ", [$gene_id]);

#
# test the storage of empty attrib values
#
{
  my %args = (-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2');
  my $current_rows = count_rows($db, 'gene_attrib');
  my $atrib = Bio::EnsEMBL::Attribute->new(%args,);
  $aa->store_on_Gene($gene, [Bio::EnsEMBL::Attribute->new(%args, -VALUE => q{})]);
  $aa->store_on_Gene($gene, [Bio::EnsEMBL::Attribute->new(%args, -VALUE => 0)]);
  my $new_rows = count_rows($db, 'gene_attrib');
  cmp_ok($new_rows, '>', $current_rows, 'Asserting the storage of undefined attributes will always store them');
  # now remove again
  $aa->remove_from_Gene($gene);
  is_rows(0, $db, "gene_attrib", "where gene_id = ? ", [$gene_id]);

}

#
# Test batch storage
#

my $gene2 = $ga->fetch_by_stable_id($stable_id2);
my $batch = {$gene->dbID()  => [Bio::EnsEMBL::Attribute->new(-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2', VALUE => 'val1'), Bio::EnsEMBL::Attribute->new(-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2', VALUE => 'val2')],
			 $gene2->dbID() => [Bio::EnsEMBL::Attribute->new(-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2', VALUE => 'val3'),]};
my $current_rows = count_rows($db, 'gene_attrib');
$aa->store_batch_on_Gene($batch);
my $new_rows = count_rows($db, 'gene_attrib');
cmp_ok($new_rows, '=', $current_rows + 3, 'Asserting the storage of multiple attributes will always store them');

@attribs = @{$aa->fetch_all_by_Gene($gene)};
is(@attribs, 2, "Two attribs available for gene");

@attribs = @{$aa->fetch_all_by_Gene($gene2)};
is(@attribs, 1, "One attrib stored for gene2");

my $slice2 = $slice_adaptor->fetch_by_region('chromosome', 'X');
my $batch = {$slice->get_seq_region_id()  => [Bio::EnsEMBL::Attribute->new(-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2', VALUE => 'val1'), Bio::EnsEMBL::Attribute->new(-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2', VALUE => 'val2')],
                         $slice2->get_seq_region_id() => [Bio::EnsEMBL::Attribute->new(-NAME => 'test_name2', -CODE => 'test_code2', -DESCRIPTION => 'test_desc2', VALUE => 'val3'),]};
my $current_rows = count_rows($db, 'seq_region_attrib');
$aa->store_batch_on_Slice($batch);
my $new_rows = count_rows($db, 'seq_region_attrib');
cmp_ok($new_rows, '=', $current_rows + 3, 'Asserting the storage of multiple attributes will always store them');

@attribs = @{$aa->fetch_all_by_Slice($slice)};
is(@attribs, 2, "Two attribs available for slice");

@attribs = @{$aa->fetch_all_by_Slice($slice2)};
is(@attribs, 1, "One attrib stored for slice2");

$multi->restore($dbtype, 'misc_attrib', 'seq_region_attrib', 'attrib_type');

done_testing();
