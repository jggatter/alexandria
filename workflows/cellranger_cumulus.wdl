version 1.0

import "https://api.firecloud.org/ga4gh/v1/tools/cumulus:cellranger_workflow/versions/10/plain-WDL/descriptor" as cellranger
import "https://api.firecloud.org/ga4gh/v1/tools/cumulus:cumulus/versions/18/plain-WDL/descriptor" as cumulus

workflow cellranger_cumulus {
	input {
		# 5 - 8 columns (Sample, Reference, Flowcell, Lane, Index, [Chemistry, DataType, FeatureBarcodeFile]). gs URL
		File input_csv_file

		# Output bucket
	  	String bucket

		String output_path

		String fastq_directory = ''

		Boolean run_cellranger

		Boolean run_cumulus

		String cumulus_output_prefix = "crc"

		### Docker image information. Addresses are formatted as <registry name>/<image name>:<version tag>
		# cellranger_workflow docker image: <cellranger_registry>/cellranger:<cellranger_tools_version>
		String cellranger_registry = "cumulusprod" # https://hub.docker.com/r/cumulusprod/cellranger/tags
		String cellranger_version = "3.1.0" # https://hub.docker.com/r/cumulusprod/cellranger/tags (2.2.0, 3.0.2, or 3.1.0)
		String cellranger_mkfastq_registry = "gcr.io/broad-cumulus"
		String cellranger_atac_version = "1.2.0"

		# cumulus workflow docker image: <cumulus_registry>/cumulus:<cumulus_version>
		String cumulus_registry = "cumulusprod" # https://hub.docker.com/r/cumulusprod/cumulus/tags
		
		String cumulus_version = "0.15.0"
		 # cumulus_feature_barcoding version, default to "0.2.0"
        String cumulus_feature_barcoding_version = "0.2.0"
		# alexandria docker image: <alexandria_docker>
		String alexandria_docker = "shaleklab/alexandria:0.2" # https://hub.docker.com/repository/docker/shaleklab/alexandria/tags

		Int preemptible = 2
		String zones = "us-central1-a us-central1-b us-central1-c us-central1-f us-east1-b us-east1-c us-east1-d us-west1-a us-west1-b us-west1-c"
	}
	String bucket_slash = sub(bucket, "/+$", '')+'/'
	String output_path_slash = if output_path == '' then '' else sub(output_path, "/+$", '')+'/' 
	String fastq_directory_slash = if fastq_directory == '' then '' else sub(fastq_directory, "/+$", '')+'/'

	String base_fastq_directory_slash = sub(fastq_directory_slash, bucket_slash, '')
	String base_output_path_slash = sub(output_path_slash, bucket_slash, '')
	String cellranger_output_path_slash = base_output_path_slash+"cellranger/"
	String cumulus_output_path_slash = base_output_path_slash+"cumulus/"

	String cellranger_registry_stripped = sub(cellranger_registry, "/+$", '')
	String cellranger_mkfastq_registry_stripped = sub(cellranger_mkfastq_registry, "/+$", '')
	String bcl2fastq_registry_stripped = sub(bcl2fastq_registry, "/+$", '')
	String cumulus_registry_stripped = sub(cumulus_registry, "/+$", '')

	Boolean check_inputs = !run_cellranger

	if (run_cellranger) {
		call setup_cellranger {
			input:
				bucket_slash=bucket_slash,
				input_csv_file=input_csv_file,
				reference=reference,
				cellranger_output_path_slash=cellranger_output_path_slash,
				fastq_directory_slash=base_fastq_directory_slash,
				alexandria_docker=alexandria_docker,
				preemptible=preemptible,
				zones=zones
		}
		call cellranger.cellranger_workflow as cellranger {
			input:
				input_csv_file=setup_cellranger.cellranger_locations,
				output_directory=cellranger_output_path_slash,
				cellranger_registry=cellranger_registry_stripped,
				cellranger_version=cellranger_version,
				mkfastq_docker_registry=cellranger_mkfastq_registry_stripped,
				cellranger_atac_version=cellranger_atac_version,
				cumulus_feature_barcoding=cumulus_feature_barcoding,
				preemptible=preemptible,
				zones=zones
		}
	}
	if (run_cumulus) {
		# Check user input_csv_file if check_inputs==true and create count_matrix.csv for Cumulus
		call setup_cumulus {
			input: 
				check_inputs=check_inputs,
				input_csv_file=input_csv_file,
				reference=reference,
				bucket_slash=bucket_slash,
				cellranger_output_path_slash=cellranger_output_path_slash,
				cumulus_output_path_slash=cumulus_output_path_slash,
				sample_ids=cellranger.sample_ids
				alexandria_docker=alexandria_docker,
				preemptible=preemptible,
				zones=zones
		}
		call cumulus.cumulus as cumulus {
			input:
				input_file=setup_cumulus.count_matrix,
				output_name=bucket_slash + cumulus_output_path_slash + cumulus_output_prefix,
				generate_scp_outputs=true,
				output_dense=true,
				preemptible=preemptible,
				zones=zones,
				docker_registry=cumulus_registry_stripped,
				cumulus_version=cumulus_version
		}
		# Segregate the output scp files and map the input_csv_file's metadata to create the alexandria_metadata.txt
		call scp_outputs {
			input:
				input_csv_file=input_csv_file,
				bucket_slash=bucket_slash,
				cumulus_output_path_slash=cumulus_output_path_slash, 
				output_scp_files=cumulus.output_scp_files,
				alexandria_docker=alexandria_docker,
				preemptible=preemptible,
				zones=zones
		}
	}
	output {
		#Array[String?]? raw_matrices = cellranger.sample_ids
		# Array[String?]? cumulus_matrices = cumulus.???
		String? cellranger_output_path = bucket_slash+cellranger_output_path_slash
		String? cumulus_output_path = bucket_slash+cumulus_output_path_slash
		
		File? alexandria_metadata = scp_outputs.alexandria_metadata
		File? fitsne_coords = scp_outputs.fitsne_coords
		File? dense_matrix = scp_outputs.dense_matrix
		File? cumulus_metadata = scp_outputs.cumulus_metadata
 	}
}

task setup_cellranger {
	
	String bucket_slash
	Boolean is_bcl
	File input_csv_file
	String reference
	String cellranger_output_path_slash
	String? fastq_directory_slash
	String alexandria_docker
	Int preemptible
	String zones
	
	command {
		set -e
		python /alexandria/scripts/setup_tool.py \
			-t=cellranger \
			-i=~{input_csv_file} \
			-g=~{bucket_slash} \
			~{true="--is_bcl" false='' is_bcl} \
			-m=/alexandria/scripts/metadata_type_map.tsv \
			-f=~{fastq_directory_slash} \
			-r=~{reference}
		gsutil cp cellranger_locations.tsv ~{bucket_slash}~{cellranger_output_path_slash}
	}
	output {
		File cellranger_locations = "cellranger_locations.tsv"
	}
	runtime {
		docker: "~{alexandria_docker}"
		preemptible: "~{preemptible}"
		zones: "~{zones}"
	}
}

task setup_cumulus {
	
	Boolean check_inputs
	File input_csv_file
	String reference
	String bucket_slash
	String cellranger_output_path_slash
	String cumulus_output_path_slash
	String alexandria_docker
	Int preemptible
	String zones
	Array[String?]? sample_ids
	
	command {
		set -e
		python /alexandria/scripts/setup_cumulus.py \
			-i=~{input_csv_file} \
			-t=cellranger \
			-g=~{bucket_slash} \
			~{true="--check_inputs" false='' check_inputs} \
			-r=~{reference} \
			-m=/alexandria/scripts/metadata_type_map.tsv \
			-o=~{cellranger_output_path_slash}
		gsutil cp count_matrix.csv ~{bucket_slash}~{cumulus_output_path_slash}
	}
	output {
		File count_matrix = "count_matrix.csv"
	}
	runtime {
		docker: "~{alexandria_docker}"
		preemptible: "~{preemptible}"
		zones: "~{zones}"
	}
}

task scp_outputs {
	
	File input_csv_file
	String cumulus_output_path_slash
	Array[File] output_scp_files
	String bucket_slash
	String alexandria_docker
	Int preemptible
	String zones
	
	command {
		set -e
		printf "~{sep='\n' output_scp_files}" >> output_scp_files.txt
		python /alexandria/scripts/scp_outputs.py \
			-t cellranger \
			-i ~{input_csv_file} \
			-s output_scp_files.txt \
			-m /alexandria/scripts/metadata_type_map.tsv
		gsutil cp alexandria_metadata.txt ~{bucket_slash}~{cumulus_output_path_slash}
	}
	output {
		File alexandria_metadata = "alexandria_metadata.txt"
		File cumulus_metadata = read_string("metadata.txt")
		File fitsne_coords = read_string("X_fitsne.coords.txt")
		File dense_matrix = read_string("expr.txt")
	}
	runtime {
		docker: "~{alexandria_docker}"
		preemptible: "~{preemptible}"
		zones: "~{zones}"
	}
}