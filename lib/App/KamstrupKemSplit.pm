package App::KamstrupKemSplit;

#VERSION
use Modern::Perl;
use Log::Log4perl qw(:easy);
use Text::CSV;
use Archive::Zip qw(:ERROR_CODES);
use XML::Simple;
use Crypt::Rijndael;
use MIME::Base64;
use Exporter qw(import);
our @EXPORT = qw(split_order read_config unzip_kem decode_kem parse_xml_string_to_data);

sub unzip_kem {
	my $input_file = shift();

	# Unzip the file
	INFO "Opening $ input_file archive file...";
	my $zip    = Archive::Zip->new();
	my $status = $zip->read($input_file);
	LOGDIE "Read of $input_file failed\n" if $status != AZ_OK;

	# There should be only a single kem in the zipfile
	my @kems = $zip->membersMatching('.*\.kem');
	LOGDIE "Please examine the zipfile, it does not contain a single kem file"
	  if ( scalar(@kems) != 1 );
	my $filename = $kems[0]->{'fileName'};
	DEBUG "Kem filename in archive : " . $filename . " -> unzip";
	$status = $zip->extractMemberWithoutPaths($filename);
	LOGDIE "Extracting $filename from archive failed\n" if $status != AZ_OK;
	return $filename;
}

sub decode_kem {
	my $input_file = shift();
	my $key        = shift();
	my $kem_xml    = XMLin($input_file);
	DEBUG "Decoding encrypted section from XML with key '$key'";
	my $data    = decode_base64( $kem_xml->{CipherData}->{CipherValue} );
	my $fullkey = $key . ( "\0" x ( 16 - length($key) ) );
	my $cipher  = Crypt::Rijndael->new( $fullkey, Crypt::Rijndael::MODE_CBC() );
	my $plain_xml = $cipher->decrypt($data);

	# Fix the XML
	substr( $plain_xml, 0, 14 ) = "<MetersInOrder";
	chomp($plain_xml);

	# Remove trailing characters after last closing bracket in the XML
	if ( $plain_xml =~ /(<.+>)/ ) {
		$plain_xml = $1;
	}
	return $plain_xml;
}

sub split_order {
	my $meters = shift();
	my $nr_min = shift();
	my $nr_max = shift();
	my $response;
	foreach my $meter ( @{ $meters->{'Meter'} } ) {
		if ( $meter->{'MeterNo'} >= $nr_min && $meter->{'MeterNo'} <= $nr_max )
		{
			$response->{$meter} = $meter;
		}
	}
	return $response;
}

sub read_config {
	my $csv_file = shift();

	# Init the CSV reader
	my $csv = Text::CSV->new(
		{
			binary             => 1,
			auto_diag          => 1,
			sep_char           => ';',
			allow_loose_quotes => 1,
		}
	);
	open( my $data, '<:encoding(utf8)', $csv_file )
	  or LOGDIE "Could not open '$csv_file' $!\n";
	INFO "Reading config file '$csv_file'";

	# Fetch the header to determine at what position the useful data is
	# Required headers are listed below
	my @reflist = (
		'kamstrup_ordernr',           'kamstrup_serial_number_start',
		'kamstrup_serial_number_end', 'number_of_devices',
		'internal_batch_number'
	);
	my $fields = $csv->getline($data);
	my $index;
	my $entries = 0;
	my $idx     = 0;
	foreach my $field ( @{$fields} ) {
		$index->{$field} = $idx;
		$idx++;
	}
	my $content;

	# Check all headers are present
	foreach my $label (@reflist) {
		if ( !defined $index->{$label} ) {
			LOGDIE
"Input configuration file does not contain a column with label $label! Quitting...";
		}
	}

	# Parse the file data based on the header information
	while ( my $fields = $csv->getline($data) ) {
		my $kamstrup_ordernr = $fields->[ $index->{'kamstrup_ordernr'} ];
		my $kamstrup_start =
		  $fields->[ $index->{'kamstrup_serial_number_start'} ];
		my $kamstrup_stop = $fields->[ $index->{'kamstrup_serial_number_end'} ];
		my $internal_batchnr = $fields->[ $index->{'internal_batch_number'} ];
		my $nr_of_devices    = $fields->[ $index->{'number_of_devices'} ];
		if (   defined $kamstrup_ordernr
			&& defined $kamstrup_start
			&& defined $kamstrup_stop
			&& defined $internal_batchnr )
		{
			$content->{$internal_batchnr} = {
				'kamstrup_ordernr' => $kamstrup_ordernr,
				'kamstrup_start'   => $kamstrup_start,
				'kamstrup_stop'    => $kamstrup_stop,
				'nr_of_devices'    => $nr_of_devices
			};
		} else {
			WARN
"Skipping line $. of input file because it does not contain the required fields";
		}
	}
	close($data);
	return $content;
}

sub parse_xml_string_to_data {
	my $xml = shift();

	# Write XML to output in order to be able to read it back as data structure
	open( my $fh, '>', "decoded.xml" ) or die "Could not open output file: $!";
	print $fh $xml;
	close $fh;

	# Parse the written XML to data structure
	my $meters = XMLin( "decoded.xml", ForceArray => ['Meter'] );
	unlink 'decoded.xml';
	return $meters;
}

sub print_xml_to_file {
	
}
1;
