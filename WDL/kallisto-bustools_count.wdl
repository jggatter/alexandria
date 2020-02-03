# Kallisto-Bustools count subworkflow
# A publicly available WDL workflow made by Shalek Lab for Kallisto and Bustools
# Workflow by jgatter [at] broadinstitute.org, created November 2019
# FULL DISCLOSURE: many optional parameters remain untested, contact me with bug reports or feature requests
# Kallisto and Bustools made by Pachter Lab. Documentation: https://www.kallistobus.tools/kb_getting_started.html
# -----------------------------------------------------------------------------------------------------------
# COUNT INSTRUCTIONS: Align your reads and generate a count matrix (use_lamanno=true for RNA velocity)
# ex: kb count --verbose (--lamanno) -i index.idx -g transcripts_to_genes.txt -x DROPSEQ -t 32 -m 256G --filter bustools -o ~/count (use_lamanno==true: c1 cDNA_t2c.txt -c2 intron_t2c.txt) R1.fastq.gz (R2.fastq.gz)
# Inputs: All outputs from the ref step, technology (“DROPSEQ”, “10XV3”, “10XV2”, see kb --list for more), R1_fastq, optional R2_fastq, set use_lamanno=true for RNA velocity,
#	Set nucleus to true for calculating RNA velocity on single-nucleus RNA-seq reads 
#	h5ad or loom to true for outputting expression matrices in those formats.	
#	Barcode whitelist for Seq-Well data will be generated by the program, but if you have one for 10X data you can provide it as an input.
# 	There are several memory parameters you can tweak, but I haven’t noticed any improvements in speed when adjusting them. I’ll investigate it eventually.
#	Specifically, for running with use_lamanno, memory/disk space parameters may require tweaking! Let me know!
# Outputs: Count matrices filtered and unfiltered with their respective barcode and gene lists. Many other files as well.
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 15
# Upped memory, disk space, boot disk size
# Added delete_bus_files
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 16
# Changed ~/kb to ~/count
# Took away default for delete_bus_files. If you think it should be true/false by default, please let me know
# Added count_output_path output
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 17
# Added sample_name for scattering purposes. See newest kallisto-bustools.wdl for scattering of sample_sheet.
# output_path that may contain bucket in the string now removes that substring.
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 18
# Fixed output_path_slash and program_memory
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 19
# Added empty string handling for output_path_slash
# Removed default value for use_lamanno
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 20
# Moved modifications of parameters outside of workflow inputs
# -----------------------------------------------------------------------------------------------------------
# SNAPSHOT 21
# Adjusted memory parameters
# Renamed boot_disk_size_gb to boot_disk_size_GB
# -----------------------------------------------------------------------------------------------------------

version 1.0

workflow kallisto_bustools_count {
	input {
		String docker = "shaleklab/kallisto-bustools:0.24.4"
		Int number_cpu_threads = 32
		Int task_memory_GB = 256
		Int preemptible = 2
		String zones = "us-east1-d us-west1-a us-west1-b"
		String disks = "local-disk 256 SSD"
		Int boot_disk_size_GB = 100

		String bucket
		String output_path

		File index
		File T2G_mapping
		String technology # DROPSEQ, 10XV1, 10XV2, 10XV3 or see kb --list for more
		File R1_fastq

		String? sample_name
		File? R2_fastq
		File? barcodes_whitelist
		Boolean use_lamanno
		File? cDNA_transcripts_to_capture
		File? intron_transcripts_to_capture
		Boolean nucleus=false
		Boolean bustools_filter=true
		Boolean loom=false
		Boolean h5ad=false
		Boolean delete_bus_files
	}
	String bucket_slash = sub(bucket, "/+$", '') + '/'
	String output_path_slash = if output_path == '' then '' else sub(output_path, "/+$", '') + '/'
	String base_output_path_slash = sub(output_path_slash, bucket_slash, '')
	Int program_memory_GB = task_memory_GB * 5 / 6

	call count {
		input:
			docker=docker,
			number_cpu_threads=number_cpu_threads,
			task_memory_GB=task_memory_GB,
			program_memory_GB=program_memory_GB,
			preemptible=preemptible,
			zones=zones,
			disks=disks,
			boot_disk_size_GB=boot_disk_size_GB,
			bucket_slash=bucket_slash,
			output_path_slash=base_output_path_slash,
			index=index,
			T2G_mapping=T2G_mapping,
			technology=technology,
			R1_fastq=R1_fastq,
			sample_name=sample_name,
			R2_fastq=R2_fastq,
			barcodes_whitelist=barcodes_whitelist,
			use_lamanno=use_lamanno,
			cDNA_transcripts_to_capture=cDNA_transcripts_to_capture,
			intron_transcripts_to_capture=intron_transcripts_to_capture,
			nucleus=nucleus,
			bustools_filter=bustools_filter,
			loom=loom,
			h5ad=h5ad,
			delete_bus_files=delete_bus_files
	}
	output {
		File counts_unfiltered_matrix = count.counts_unfiltered_matrix
		File counts_filtered_matrix = count.counts_filtered_matrix
		String count_output_path = count.count_output_path
	}
}

task count {
	input {
		String docker
		Int number_cpu_threads
		Int task_memory_GB
		Int program_memory_GB
		Int preemptible
		String zones
		String disks
		Int boot_disk_size_GB

		String bucket_slash
		String output_path_slash
		File index
		File T2G_mapping
		String technology
		File R1_fastq
		
		String? sample_name
		File? R2_fastq
		File? barcodes_whitelist
		Boolean use_lamanno
		File? cDNA_transcripts_to_capture
		File? intron_transcripts_to_capture
		Boolean nucleus
		Boolean bustools_filter
		Boolean loom
		Boolean h5ad
		Boolean delete_bus_files
	}
	command {
		set -e
		export TMPDIR=/tmp

		mkdir ~/count~{'_'+sample_name}
		kb count --verbose \
			-i ~{index} \
			-g ~{T2G_mapping} \
			-x ~{technology} \
			-o ~/count~{'_'+sample_name} \
			~{"-w "+barcodes_whitelist} \
			~{true="--lamanno" false='' use_lamanno} \
			~{"-c1 "+cDNA_transcripts_to_capture} \
			~{"-c2 "+intron_transcripts_to_capture} \
			~{true="--nucleus" false='' nucleus} \
			~{true="--filter bustools" false='' bustools_filter} \
			~{true="--loom" false='' loom} \
			~{true="--h5ad" false='' h5ad} \
			~{"-t "+number_cpu_threads} \
			~{"-m "+program_memory_GB+'G'} \
			~{R1_fastq} \
			~{R2_fastq}

		if [ "~{delete_bus_files}" = "true" ]; then
			rm -vf ~/count~{'_'+sample_name}/*.bus
		fi
		gsutil mv ~/count~{'_'+sample_name} ~{bucket_slash}~{output_path_slash}
	}
	output {
		String count_output_path = "~{bucket_slash}~{output_path_slash}count~{'_'+sample_name}/"
		String counts_unfiltered_matrix = "~{bucket_slash}~{output_path_slash}count~{'_'+sample_name}/counts_unfiltered/cells_x_genes.mtx"
		String counts_filtered_matrix = "~{bucket_slash}~{output_path_slash}count~{'_'+sample_name}/counts_filtered/cells_x_genes.mtx"
	}
	runtime {
		docker: "~{docker}"
		preemptible: preemptible
		memory: "~{task_memory_GB}G"
		zones: "~{zones}"
		bootDiskSizeGb: boot_disk_size_GB
		failOnStderr: true
		disks: "~{disks}"
		cpu: number_cpu_threads
	}
}