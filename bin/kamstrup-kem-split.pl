#! /usr/bin/env perl

# This script decodes a Kamstrup KEM file.
# Way to proceed starting from a fresh KEM file:
#  * unzip the .zip.kem file (adapt the extension and unzip)
#  * this results in a folder with an XML file and an XML template
#  * run this scrip on the folder, passing the key that is printed on the delivery note of the meters (delivered with the meters)
#
# Example: ./decode_kem.pl --key 0310482W 2902912F963E46F3B1B4A1C3DA47585A

use strict;
use warnings;

use 5.030;

use App::KamstrupKemSplit;
use Log::Log4perl qw(:easy);
use XML::Simple;


use Getopt::Long;
use Pod::Usage;
use Data::Dumper;

my ($key, $verbose, $help, $man, $config);

# Default values
$verbose = 0;

# Get the command line options
GetOptions(
    'help|?|h'   => \$help,
    'man'        => \$man,
    'v|verbose'  => \$verbose,
    'key=s'		 => \$key,
    'config=s'   => \$config
) or pod2usage(2);

if ($verbose) {
	Log::Log4perl->easy_init($DEBUG);
	INFO "Starting in verbose mode";
} else {
   	Log::Log4perl->easy_init($INFO);
}

# Open the config file
my $orders = read_config($config);

# Unzip it
my $kem_file = unzip_kem($ARGV[0]);

# Decode the kem file from the archive
my $xml = decode_kem($kem_file, $key);


# Fix the XML
substr($xml, 0, 14) = "<MetersInOrder";
chomp($xml);

# Remove trailing characters after last closing bracket in the XML
if ($xml =~ /(<.+>)/) {
	$xml = $1;
}


open (my $fh, '>', "decoded.xml") or die "Could not open output file: $!";
print $fh  $xml;
close $fh;


# Parse the XML
my $meters = XMLin("decoded.xml", ForceArray => ['Meter']);
unlink 'decoded.xml';

#print Dumper($meters);

# Prepare minimal datastructure for XML dump
my $skeleton;
# = dclone $meters;
#$skeleton->{'Meter'} = {};


foreach my $order (sort keys %{$orders}) {
	DEBUG "Processing batch $order";
	my $meterinfo = split_order($meters, $orders->{$order}->{'kamstrup_start'}, $orders->{$order}->{'kamstrup_stop'});
	
	# Sanity check on the number of devices
	if (scalar( keys %{$meterinfo} ) != $orders->{$order}->{'nr_of_devices'}) {
		LOGDIE "Expecting " . $orders->{$order}->{'nr_of_devices'} . " devices in batch $order but found " . scalar(keys %{$meterinfo}) . " in XML file";
	}
	INFO "Dumping info from order # $order for " . scalar(keys %{$meterinfo}) . " devices";
	$skeleton->{'orderid'} = $meters->{'orderid'} . "_" . "$order";
	$skeleton->{'Meter'}   = $meterinfo;
	
	my $xml = XMLout($skeleton, 'noattr' => 1, KeyAttr => ["MeterNo"]);
	#my $xml = perl2xml($skeleton);
	$xml =~ s/opt/MetersInOrder/g; # Replace the default 'opt' by 'MetersInOrder'
	$xml =~ s/\<orderid.+orderid\>\s+//; # Strip orderid line
	$xml =~ s/\<schemaVersion.+schemaVersion\>\s+//; # Strip orderid line
	$xml =~ s/\<MetersInOrder\>//; # Strip first line, we will replace it with a custom line to match the original XML output
	$xml = '<?xml version="1.0" encoding="utf-8"?>' . "\n<MetersInOrder orderid=\"$skeleton->{'orderid'}\" schemaVersion=\"2.0\">" . $xml;
	print $xml;
	
	my $fh = IO::File->new("> " . $skeleton->{'orderid'} . ".xml");
	if (defined $fh) {
    	print $fh $xml;
    	$fh->close;
	} else {
		LOGDIE "Could not write to outputfile: $!";
	}
}


# Remove the unzipped file
unlink $kem_file;


exit(0);

#sub split_order {
#	my $meters = shift();
#	my $nr_min = shift();
#	my $nr_max = shift();
#	
#	my $response;
#	
#	foreach my $meter (%{$meters}) {
#		if ($meter >= $nr_min && $meter <= $nr_max) {
#			$response->{$meter} = $meters->{$meter};
#		}
#	}
#	
#	return $response;
#}

#my $data = "liAPxu7rk/nbyfaYDWlca8TjRh8cMThmh9P8v3x+SxeGxdlF39xyc8nsGN+aMrcPOl9Q8Arf9UsYhSYvZB5mTu/LOdSTZ3LRQ9RxlMJZPcsVvKdxTG7lrmRHLABiwOai/K6m9dTJmwCgvB37L0uVd9ZTRBacIcgLJfXVCARs1/bdoQtG7yMM/M7zJqmzTFhaO2CzmRitC69lYAgtwktjfMmx3RtPeg5MBg/juendilyUJbn5o+YM+drw11WORUf8mS89e/OzRYak2m1/junqwWVwQFWaX0WSA+WAui9vE+c77sBGRx0IOof/R6rqY3pX9SgOGNPPPwefZbBQ/H+7OVdsr4gmHaiCS76q+t3kwxW1lGkwdTiMEzOFf+sbBYlw0pOZiYqlTg5lu8B+ZR3/9mPH7uli+wSeeVm6oa5m93nMBNEMgrf+vTd0IZ0WsfhjtjXYauMLPMJPlXxfC0VyFFoZ4RKDcsc6UDbEWZEP/qTl0c/K8as1wgyh+4YtfxpCHk8LryVDtQJ8Y3A+kRklrlWvs0NzwyeeEnyziMhpramOefkARavHA9UaY+V+0GkHy404J3XXj1M5Viy6LrNCkanCaeP41K6YSvXrJ2WrCDhhCm/D5rSFhrzsy+hM2Hk9H/AGvoMOSX2oaW5ouYcRyVl0r5UtDB4xBTiYyzncf7sHyz6lgvDepZfcLtx4Tbl6sfzwRVKlU9F8svXMVk/VjuAXNspC5h7VSzRQYb+WvuFv8M4OcITc76Fd2rrS19pbvWWG7ER/K4ksfKl1kTGMglRM6KkVFhKNlNZ//thimPB6/ucoZYmfzbfuPdQcKyQBm3odyzv/aoO2+704kRk7Pf/S7K1/CPHnMz5RUD8WFVIRIFPvamklV0u7YrPgi99I9VAur+Ox3l62foPidPdInQ==";
#my $data_decoded = decode_base64($data);
#
#print "Data length: " . length($data_decoded) . "\n\n";
#
#my $key = "0450284H";
#
#my $cipher = Crypt::Rijndael->new('0450284H' ^ ("\0"x16), Crypt::Rijndael::MODE_CBC());
#
#my $plaintext = $cipher->decrypt($data_decoded);
#
#print "---\n";
#print $plaintext;
#print "\n---\n";
#
#
##Fix the xml:
#
#substr($plaintext, 0, 14) = "<MetersInOrder";
#
#print "---\n";
#print $plaintext;
#print "\n---\n"

#sub read_config {
#	
#	my $csv_file = shift();
#	
#	# Init the CSV reader 
#	my $csv = Text::CSV->new ({
#  		binary    => 1,
#  		auto_diag => 1,
#  		sep_char  => ';',
#  		allow_loose_quotes => 1,
#	});
# 
#	open(my $data, '<:encoding(utf8)', $csv_file) or LOGDIE "Could not open '$csv_file' $!\n";
#
#	# Fetch the header to determine at what position the useful data is, we need Data, Device ID and Timestamp
#	my $fields = $csv->getline( $data );
#	my $index;
#	my $entries = 0;
#
#	my $idx = 0;
#	foreach my $field (@{$fields}) {
#		$index->{$field} = $idx;
#		$idx++;
#	}
#	
#	my $content;
#	
#	my @reflist = ('kamstrup_ordernr','kamstrup_serial_number_start','kamstrup_serial_number_end','nr_of_devices','hydroko_batchnr');
#	
#	foreach my $label (@reflist) {
#		if (!defined $index->{$label}) {
#			LOGDIE "Input configuration file does not contain a column with label $label! Quitting...";
#		}
#	}
#	
#	while (my $fields = $csv->getline( $data )) {
#		my $kamstrup_ordernr = $fields->[$index->{'kamstrup_ordernr'}];
#		my $kamstrup_start   = $fields->[$index->{'kamstrup_serial_number_start'}];
#		my $kamstrup_stop    = $fields->[$index->{'kamstrup_serial_number_end'}];
#		my $hydroko_batchnr  = $fields->[$index->{'hydroko_batchnr'}];
#		my $nr_of_devices    = $fields->[$index->{'nr_of_devices'}];
#
#		if (defined $kamstrup_ordernr && defined $kamstrup_start && defined $kamstrup_stop && defined $hydroko_batchnr) {
#	    	$content->{$hydroko_batchnr} = { 'kamstrup_ordernr' => $kamstrup_ordernr, 'kamstrup_start' => $kamstrup_start, 'kamstrup_stop' => $kamstrup_stop, 'nr_of_devices' => $nr_of_devices};
#		} else {
#			WARN "Skipping line $. of input file because it does not contain the required fields";
#		}
#	}	
#	
#	close($data);
#	
#	return $content;
#	
#}

