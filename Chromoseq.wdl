workflow ChromoSeq {

  # This is the path of the illumina run directory on staging drive of dragen node after rsync from storage0
  String? RunDir

  # Illumina-compatible fastq_list.csv, take fastq list as input instead of RunDir
  String? FastqList
   
  # Illumina-compatible samplesheet for demuxing, prepared from launcher script using excel spreadsheet as input
  String? SampleSheet

  # lane, if one is specified
  String? Lane

  # array of genders. Will have to be prepared from excel spreadsheet
  Array[String] Genders

  # sample names
  Array[String] Samples

  # name of batch
  String Batch

  # The root directory where all the batches are stored
  String SeqDir
  
  # The batch output directory
  String BatchDir = SeqDir + '/' + Batch
  
  String DBSNP     = "/staging/runs/Chromoseq/dragen_align_inputs/hg38/dbsnp.vcf.gz"
  String DOCM      = "/staging/runs/Chromoseq/dragen_align_inputs/hg38/docm.vcf.gz"
  String NoiseFile = "/staging/runs/Chromoseq/dragen_align_inputs/hg38/dragen_v1.0_systematic_noise.nextera_wgs.120920.bed.gz"

  String Translocations
  String GenesBed
  
  String Cytobands
  String SVDB

  String CustomAnnotationVcf 
  String CustomAnnotationIndex
  String CustomAnnotationParameters
  String? GeneFilterString
  
  String HotspotVCF
  String MantaConfig
  String MantaRegionConfig
  
  String HaplotectBed
  
  String Reference
  String ReferenceDict
  String ReferenceIndex
  String ReferenceBED

  String DragenReference    = "/staging/runs/Chromoseq/refdata/dragen_hg38"
  String DragenReferenceBED = "/staging/runs/Chromoseq/refdata/dragen_hg38/all_sequences.fa.bed.gz"
  String VEP

  String gcWig
  String mapWig
  String ponRds
  String centromeres
  String genomeStyle
  String genome

  String tmp
  
  Float minVarFreq
  Int MinReads
  Float varscanPvalindel
  Float varscanPvalsnv

  Int CNAbinsize = 500000
  Int MinCNASize = 5000000
  Float MinCNAabund = 10.0

  Int MinValidatedReads
  Float MinValidatedVAF

  Int MinCovFraction
  Int MinGeneCov
  Int MinRegionCov
  
  String JobGroup
  String Queue
  String DragenQueue

  String chromoseq_docker
  String DragenDocker

  call prepare_bed {
    input: Bedpe=Translocations,
    Bed=GenesBed,
    Reference=ReferenceBED,
    queue=Queue,
    jobGroup=JobGroup,
    tmp=tmp,
    docker=chromoseq_docker
  }

  call dragen_demux {
    input: rundir=RunDir,
    FastqList=FastqList,
    Batch=Batch,
    sheet=SampleSheet,
    lane=Lane,
    jobGroup=JobGroup,
    queue=DragenQueue,
    docker=DragenDocker
  }

  scatter(i in range(length(Samples))){
    call dragen_align {
      input: BatchDir=BatchDir,
      Batch=Batch,
      fastqfile=dragen_demux.fastqfile,
      sample=Samples[i],
      gender=Genders[i],
      Reference=DragenReference,
      ReferenceBed=DragenReferenceBED,
      CNAbinsize=CNAbinsize,
      DBSNP=DBSNP,
      DOCM=DOCM,
      NoiseFile=NoiseFile,
      jobGroup=JobGroup,
      queue=DragenQueue,
      docker=DragenDocker
    }

    call cov_qc as gene_qc {
      input: Cram=dragen_align.cram,
      CramIndex=dragen_align.index,
      Name=Samples[i],
      Bed=GenesBed,
      refFasta=Reference,
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }

    call cov_qc as sv_qc {
      input: Cram=dragen_align.cram,
      CramIndex=dragen_align.index,
      Name=Samples[i],
      Bed=prepare_bed.svbed,
      refFasta=Reference,
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }
    
    call run_manta {
      input: Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      Config=MantaConfig,
      Reference=Reference,
      ReferenceBED=ReferenceBED,
      Name=Samples[i],
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }

    call run_ichor {
      input: Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      refFasta=Reference,
      ReferenceBED=ReferenceBED,
      tumorCounts=dragen_align.counts,
      gender=Genders[i],
      gcWig=gcWig,
      mapWig=mapWig,
      ponRds=ponRds,
      centromeres=centromeres,
      Name=Samples[i],
      genomeStyle=genomeStyle,
      genome=genome,
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }
    
    call run_varscan_indel {
      input: Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      CoverageBed=GenesBed,
      MinFreq=minVarFreq,
      pvalindel=varscanPvalindel,
      refFasta=Reference,
      Name=Samples[i],
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }

    call run_varscan_snv {
      input: Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      CoverageBed=GenesBed,
      MinFreq=minVarFreq,
      pvalsnv=varscanPvalsnv,
      refFasta=Reference,
      Name=Samples[i],
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }
    
    call run_manta_indels {
      input: Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      Reg=GenesBed,
      Config=MantaRegionConfig,
      refFasta=Reference,
      Name=Samples[i],
      genome=genome,
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }

    call run_pindel_indels {
      input: Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      Reg=GenesBed,
      refFasta=Reference,
      Name=Samples[i],
      genome=genome,
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }

    call combine_variants {
      input: VCFs=[run_varscan_snv.vcf,
      run_varscan_indel.vcf,run_pindel_indels.vcf,
      run_manta_indels.vcf,
      HotspotVCF],
      MinVAF=minVarFreq,
      MinReads=MinReads,
      Bam=dragen_align.cram,
      BamIndex=dragen_align.index,
      refFasta=Reference,
      Name=Samples[i],
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }
    
    call annotate_variants {
      input: Vcf=combine_variants.combined_vcf_file,
      refFasta=Reference,
      Vepcache=VEP,
      Cytobands=Cytobands,
      CustomAnnotationVcf=CustomAnnotationVcf,
      CustomAnnotationIndex=CustomAnnotationIndex,
      CustomAnnotationParameters=CustomAnnotationParameters,
      FilterString=GeneFilterString,
      Name=Samples[i],
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }
    
    call annotate_svs {
      input: Vcf=run_manta.vcf,
      CNV=run_ichor.seg,
      refFasta=Reference,
      refFastaIndex=ReferenceIndex,
      Vepcache=VEP,
      SVAnnot=SVDB,
      Translocations=Translocations,
      Cytobands=Cytobands,
      minCNAsize=MinCNASize,
      minCNAabund=MinCNAabund,
      Name=Samples[i],
      gender=Genders[i],
      queue=Queue,
      jobGroup=JobGroup,
      tmp=tmp,
      docker=chromoseq_docker
    }
    
    call run_haplotect {
      input: refFasta=Reference,
      refDict=ReferenceDict,
      Cram=dragen_align.cram,
      CramIndex=dragen_align.index,
      Bed=HaplotectBed,
      Name=Samples[i],
      queue=Queue,
      jobGroup=JobGroup
    }

    call make_report {
      input: SVVCF=annotate_svs.vcf,
      GeneVCF=annotate_variants.annotated_filtered_vcf,
      KnownGenes=prepare_bed.genes,
      GeneQC=gene_qc.qc_out,
      SVQC=sv_qc.qc_out,
      Haplotect=run_haplotect.out_file,
      MappingSummary=dragen_align.mapping_summary,
      CoverageSummary=dragen_align.coverage_summary,
      Name=Samples[i],
      MinReads=MinValidatedReads,
      MinVAF=MinValidatedVAF,
      MinFracCov=MinCovFraction,
      MinGeneCov=MinGeneCov,
      MinRegionCov=MinRegionCov,
      queue=Queue,
      jobGroup=JobGroup,
      docker=chromoseq_docker,
      tmp=tmp
    }
    
    call gather_files {
      input: OutputFiles=[annotate_svs.vcf,
      annotate_svs.vcf_index,
      annotate_svs.allvcf,
      annotate_svs.allvcf_index,
      annotate_variants.annotated_filtered_vcf,
      annotate_variants.annotated_filtered_vcf_index,
      annotate_variants.annotated_vcf,
      annotate_variants.annotated_vcf_index,
      run_ichor.params,
      run_ichor.seg,
      run_ichor.genomewide_pdf,
      run_ichor.allgenomewide_pdf,
      run_ichor.rdata,run_ichor.wig,
      run_ichor.correct_pdf,
      gene_qc.qc_out,
      gene_qc.region_dist,
      gene_qc.global_dist,
      sv_qc.qc_out,
      sv_qc.region_dist,
      run_haplotect.out_file,
      run_haplotect.sites_file,
      make_report.report],
      OutputDir=BatchDir + "/" + Samples[i],
      queue=Queue,
      jobGroup=JobGroup,
      docker=chromoseq_docker
    }
  }
  call remove_rundir {
    input: order_by=make_report.report,
    rundir=RunDir,
    queue=DragenQueue,
    jobGroup=JobGroup
  }
}

task prepare_bed {
  String Bedpe
  String Bed
  String Reference
  String queue
  String jobGroup
  String? tmp
  String docker
  
  command <<<
    awk -v OFS="\t" '{ split($7,a,"_"); print $1,$2,$3,a[1],".",$9; print $4,$5,$6,a[2],".",$10; }' ${Bedpe} | sort -u -k 1,1V -k 2,2n > sv.bed
    ((cat sv.bed | cut -f 4) && (cat ${Bed} | cut -f 6)) > genes.txt
    gunzip -c ${Reference} | cut -f 1 > chroms.txt
  >>>

  runtime {
    docker_image: docker
    cpu: "1"
    memory: "4 G"
    queue: queue
    job_group: jobGroup
  }

  output {
    File svbed = "sv.bed"
    File genes = "genes.txt"
    Array[String] chroms = read_lines("chroms.txt")
  }
}

task dragen_demux {
  String Batch
  String rootdir = "/staging/runs/Chromoseq/"
  String LocalFastqDir = rootdir + "demux_fastq/" + Batch
  String LocalFastqList = rootdir + "sample_sheet/" + Batch + '_fastq_list.csv'
  String LocalSampleSheet = rootdir + "sample_sheet/" + Batch + '.csv'
  String log = rootdir + "log/" + Batch + "_demux.log"

  String? rundir
  String? FastqList
  String? sheet
  String? lane

  String queue
  String docker
  String jobGroup

  command {
    if [ -n "${FastqList}" ]; then
      /bin/cp ${FastqList} ${LocalFastqList}
    else
      /bin/cp ${sheet} ${LocalSampleSheet}

      if [ -n "${lane}" ]; then
        /opt/edico/bin/dragen --bcl-conversion-only true --bcl-only-matched-reads true --strict-mode true --sample-sheet ${LocalSampleSheet} --bcl-input-directory ${rundir} --output-directory ${LocalFastqDir} --bcl-only-lane ${lane} &> ${log}
      else
        /opt/edico/bin/dragen --bcl-conversion-only true --bcl-only-matched-reads true --strict-mode true --sample-sheet ${LocalSampleSheet} --bcl-input-directory ${rundir} --output-directory ${LocalFastqDir} &> ${log}
      fi

      /bin/mv ${log} ./ && \
      /bin/rm -f ${LocalSampleSheet} && \
      /bin/cp "${LocalFastqDir}/Reports/fastq_list.csv" ${LocalFastqList}
    fi
  }

  runtime {
    docker_image: docker
    cpu: "20"
    memory: "200 G"
    queue: queue
    job_group: jobGroup
  }

  output {
    String fastqfile = "${LocalFastqList}"
  }
}

task dragen_align {
  String Batch
  String BatchDir

  String rootdir = "/staging/runs/Chromoseq/"
  String LocalAlignDir = rootdir + "align/" + Batch

  String fastqfile
  String sample
  String gender

  String Reference
  String ReferenceBed
  Int CNAbinsize
  String DBSNP
  String DOCM
  String NoiseFile
  String queue
  String docker
  String jobGroup

  String outdir = BatchDir + "/" + sample
  String LocalSampleDir = LocalAlignDir + "/" + sample
  String log = rootdir + "log/" + sample + "_align.log"
  
  command {
    if [ ! -d "${LocalAlignDir}" ]; then
      /bin/mkdir ${LocalAlignDir}
    fi

    if [ ! -d "${BatchDir}" ]; then
      /bin/mkdir ${BatchDir}
    fi

    /bin/mkdir ${LocalSampleDir} && \
    /opt/edico/bin/dragen -r ${Reference} --sample-sex ${gender} \
    --tumor-fastq-list ${fastqfile} --tumor-fastq-list-sample-id ${sample} \
    --enable-map-align-output true --enable-bam-indexing true --enable-duplicate-marking true \
    --enable-variant-caller true --dbsnp ${DBSNP}  --vc-somatic-hotspots ${DOCM} --vc-systematic-noise ${NoiseFile} \
    --enable-cnv true --cnv-target-bed ${ReferenceBed} --cnv-interval-width ${CNAbinsize} \
    --enable-sv true --sv-exome true --sv-output-contigs true --sv-hyper-sensitivity true \
    --output-format CRAM --output-directory ${LocalSampleDir} --output-file-prefix ${sample} &> ${log} && \
    /bin/mv ${log} ./ && \
    /bin/mv ${LocalSampleDir} ${BatchDir}
  }

  runtime {
    docker_image: docker
    cpu: "20"
    memory: "200 G"
    queue: queue
    job_group: jobGroup
  }

  output {
    File cram = "${outdir}/${sample}_tumor.cram"
    File index = "${outdir}/${sample}_tumor.cram.crai"
    File counts = "${outdir}/${sample}.target.counts.gz"
    File mapping_summary = "${outdir}/${sample}.mapping_metrics.csv"
    File coverage_summary = "${outdir}/${sample}.wgs_coverage_metrics.csv"
  }
}

task cov_qc {
  String Cram
  String CramIndex
  String Bed
  String Name
  String refFasta
  String queue
  String jobGroup
  String tmp
  String docker
  
  command <<<
    set -eo pipefail && \
    /opt/conda/bin/mosdepth -n -f ${refFasta} -t 4 -i 2 -x -Q 20 -b ${Bed} --thresholds 10,20,30,40 "${Name}" ${Cram} && \
    /usr/local/bin/bedtools intersect -header -b "${Name}.regions.bed.gz" -a "${Name}.thresholds.bed.gz" -wo | \
    awk -v OFS="\t" '{ if (NR==1){ print $0,"%"$5,"%"$6,"%"$7,"%"$8,"MeanCov"; } else { print $1,$2,$3,$4,$5,$6,$7,$8,sprintf("%.2f\t%.2f\t%.2f\t%.2f",$5/$NF*100,$6/$NF*100,$7/$NF*100,$8/$NF*100),$(NF-1); } }' > "${Name}."$(basename ${Bed} .bed)".covqc.txt" && \
    mv "${Name}.mosdepth.region.dist.txt" "${Name}.mosdepth."$(basename ${Bed} .bed)".region.dist.txt"
  >>>
  
  runtime {
    docker_image: docker
    cpu: "4"
    memory: "32 G"
    queue: queue
    job_group: jobGroup
  }
  
  output {
    File qc_out = glob("*.covqc.txt")[0]
    File global_dist = "${Name}.mosdepth.global.dist.txt"
    File region_dist = glob("*.region.dist.txt")[0]
  }
}

task run_manta {
  String Bam
  String BamIndex 
  String Config
  String Name
  String Reference
  String ReferenceBED
  String queue
  String jobGroup
  String tmp
  String docker
  
  command <<<
    set -eo pipefail && \
    /usr/local/src/manta/bin/configManta.py --config=${Config} --tumorBam=${Bam} --referenceFasta=${Reference} \
    --runDir=manta --callRegions=${ReferenceBED} --outputContig && \
    ./manta/runWorkflow.py -m local -q ${queue} -j 32 -g 32 && \
    zcat ./manta/results/variants/tumorSV.vcf.gz | /bin/sed 's/DUP:TANDEM/DUP/g' > fixed.vcf && \
    /usr/local/bin/duphold_static -v fixed.vcf -b ${Bam} -f ${Reference} -t 4 -o ${Name}.tumorSV.vcf && \
    /opt/conda/bin/bgzip ${Name}.tumorSV.vcf && /usr/bin/tabix -p vcf ${Name}.tumorSV.vcf.gz
  >>>
  runtime {
    docker_image: docker
    cpu: "4"
    memory: "32 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File vcf = "${Name}.tumorSV.vcf.gz"
    File index = "${Name}.tumorSV.vcf.gz.tbi"
  }
}

task run_ichor {
  String Bam
  String BamIndex
  String ReferenceBED
  String tumorCounts
  String refFasta
  String Name
  String gender
  String genome
  String genomeStyle
  String queue
  String jobGroup
  String gcWig
  String mapWig
  String ponRds
  String centromeres
  
  String? tmp
  String docker
  
  command <<<
    set -eo pipefail && \
    zcat ${tumorCounts} | tail -n +6 | sort -k 1V,1 -k 2n,2 | awk -v window=500000 'BEGIN { chr=""; } { if ($1!=chr){ printf("fixedStep chrom=%s start=1 step=%d span=%d\n",$1,window,window); chr=$1; } print $5; }' > "${Name}.tumor.wig" && \
    /usr/local/bin/Rscript /usr/local/bin/ichorCNA/scripts/runIchorCNA.R --id ${Name} \
    --WIG "${Name}.tumor.wig" --ploidy "c(2)" --normal "c(0.1,0.5,.85)" --maxCN 3 \
    --gcWig ${gcWig} \
    --mapWig ${mapWig} \
    --centromere ${centromeres} \
    --normalPanel ${ponRds} \
    --genomeBuild ${genome} \
    --sex ${gender} \
    --includeHOMD False --chrs "c(1:22, \"X\", \"Y\")" --chrTrain "c(1:22)" --fracReadsInChrYForMale 0.0005 \
    --estimateNormal True --estimatePloidy True --estimateScPrevalence True \
    --txnE 0.999999 --txnStrength 1000000 --genomeStyle ${genomeStyle} --outDir ./ --libdir /usr/local/bin/ichorCNA/ && \
    awk -v G=${gender} '$2!~/Y/ || G=="male"' "${Name}.seg.txt" > "${Name}.segs.txt" && \
    mv ${Name}/*.pdf .
  >>>
  
  runtime {
    docker_image: docker
    cpu: "1"
    memory: "16 G"
    queue: queue
    job_group: jobGroup
  }
  
  output {
    File params = "${Name}.params.txt"
    File seg = "${Name}.segs.txt"
    File genomewide_pdf = "${Name}_genomeWide.pdf"
    File allgenomewide_pdf = "${Name}_genomeWide_all_sols.pdf"
    File correct_pdf = "${Name}_genomeWideCorrection.pdf"
    File rdata = "${Name}.RData"
    File wig = "${Name}.tumor.wig"
  }
}

task run_varscan_snv {
  String Bam
  String BamIndex
  Int? MinCov
  Float? MinFreq
  Int? MinReads
  Float? pvalsnv
  String CoverageBed
  String refFasta
  String Name
  String queue
  String jobGroup
  String? tmp
  String docker
  
  command <<<
    /usr/local/bin/samtools mpileup -f ${refFasta} -l ${CoverageBed} ${Bam} > ${tmp}/mpileup.out && \
    java -Xmx12g -jar /opt/varscan/VarScan.jar mpileup2snp ${tmp}/mpileup.out --min-coverage ${default=6 MinCov} --min-reads2 ${default=3 MinReads} \
    --min-var-freq ${default="0.02" MinFreq} --p-value ${default="0.01" pvalsnv} --output-vcf | /opt/conda/bin/bgzip -c > ${Name}.varscan_snv.vcf.gz && /opt/conda/bin/tabix -p vcf ${Name}.varscan_snv.vcf.gz
  >>>
  
  runtime {
    docker_image: docker
    cpu: "2"
    memory: "16 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File vcf = "${Name}.varscan_snv.vcf.gz"
  }
}

task run_varscan_indel {
  String Bam
  String BamIndex
  Int? MinCov
  Float? MinFreq
  Int? MinReads
  Float? pvalindel
  String CoverageBed
  String refFasta
  String Name
  String queue
  String jobGroup
  String? tmp
  String docker
  
  command <<<
    /usr/local/bin/samtools mpileup -f ${refFasta} -l ${CoverageBed} ${Bam} > ${tmp}/mpileup.out && \
    java -Xmx12g -jar /opt/varscan/VarScan.jar mpileup2indel ${tmp}/mpileup.out --min-coverage ${default=6 MinCov} --min-reads2 ${default=3 MinReads} \
    --min-var-freq ${default="0.02" MinFreq} --p-value ${default="0.1" pvalindel} --output-vcf | /opt/conda/bin/bgzip -c > ${Name}.varscan_indel.vcf.gz && /opt/conda/bin/tabix -p vcf ${Name}.varscan_indel.vcf.gz
  >>>
  
  runtime {
    docker_image: docker
    cpu: "2"
    memory: "16 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File vcf = "${Name}.varscan_indel.vcf.gz"
  }
}

task run_pindel_indels {
  String Bam
  String BamIndex
  String Reg
  Int? Isize
  Int? MinReads
  String refFasta
  String Name
  String queue
  String jobGroup
  String tmp
  String genome
  String docker
  
  command <<<
    (set -eo pipefail && /usr/local/bin/samtools view -T ${refFasta} -ML ${Reg} ${Bam} | /opt/pindel-0.2.5b8/sam2pindel - ${tmp}/in.pindel ${default=250 Isize} tumor 0 Illumina-PairEnd) && \
    /usr/local/bin/pindel -f ${refFasta} -p ${tmp}/in.pindel -j ${Reg} -o ${tmp}/out.pindel && \
    /usr/local/bin/pindel2vcf -P ${tmp}/out.pindel -G -r ${refFasta} -e ${default=3 MinReads} -R ${default="hg38" genome} -d ${default="hg38" genome} -v ${tmp}/pindel.vcf && \
    /bin/sed 's/END=[0-9]*\;//' ${tmp}/pindel.vcf | /opt/conda/bin/bgzip -c > ${Name}.pindel.vcf.gz && /opt/conda/bin/tabix -p vcf ${Name}.pindel.vcf.gz
  >>>
  
  runtime {
    docker_image: docker
    cpu: "1"
    memory: "16 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File vcf = "${Name}.pindel.vcf.gz"
  }
}

task run_manta_indels {
  String Bam
  String BamIndex
  String Reg
  String Config
  String refFasta
  String Name
  String queue
  String jobGroup
  String tmp
  String genome
  String docker
  
  command <<<
    set -eo pipefail && 
    /opt/conda/bin/bgzip -c ${Reg} > ${tmp}/reg.bed.gz && /opt/conda/bin/tabix -p bed ${tmp}/reg.bed.gz && \
    /usr/local/src/manta/bin/configManta.py --config=${Config} --tumorBam=${Bam} --referenceFasta=${refFasta} --runDir=manta --callRegions=${tmp}/reg.bed.gz --outputContig --exome && \
    ./manta/runWorkflow.py -m local -q ${queue} -j 4 -g 32 && \
    /opt/conda/bin/python /usr/local/bin/fixITDs.py -r ${refFasta} ./manta/results/variants/tumorSV.vcf.gz | /opt/conda/bin/bgzip -c > ${Name}.manta.vcf.gz &&
    /opt/conda/bin/tabix -p vcf ${Name}.manta.vcf.gz
  >>>
  
  runtime {
    docker_image: docker
    cpu: "1"
    memory: "16 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File vcf = "${Name}.manta.vcf.gz"
  }
}

task combine_variants {
  Array[String] VCFs
  String Bam
  String BamIndex
  String refFasta
  String Name
  Int MinReads
  Float MinVAF
  String queue
  String jobGroup
  String? tmp
  String docker

  command {
    /opt/conda/envs/python2/bin/bcftools merge --force-samples -O z ${sep=" " VCFs} | \
    /opt/conda/envs/python2/bin/bcftools norm -d none -f ${refFasta} -O z > ${tmp}/combined.vcf.gz && /usr/bin/tabix -p vcf ${tmp}/combined.vcf.gz && \
    /opt/conda/bin/python /usr/local/bin/addReadCountsToVcfCRAM.py -f -n ${MinReads} -v ${MinVAF} -r ${refFasta} ${tmp}/combined.vcf.gz ${Bam} ${Name} | \
    /opt/conda/bin/bgzip -c > ${Name}.combined_tagged.vcf.gz && /usr/bin/tabix -p vcf ${Name}.combined_tagged.vcf.gz
  }
  runtime {
    docker_image: docker
    cpu: "1"
    memory: "10 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File combined_vcf_file = "${Name}.combined_tagged.vcf.gz"
  }
}

task annotate_variants {
  String Vcf
  String refFasta
  String Vepcache
  String Cytobands
  File CustomAnnotationVcf
  File CustomAnnotationIndex
  String CustomAnnotationParameters
  String? FilterString
  String Name
  String queue
  String jobGroup
  String? tmp
  String docker
  
  command {
    set -eo pipefail && \
    /usr/bin/perl -I /opt/lib/perl/VEP/Plugins /usr/bin/variant_effect_predictor.pl \
    --format vcf --vcf --fasta ${refFasta} --hgvs --symbol --term SO --per_gene -o ${Name}.annotated.vcf \
    -i ${Vcf} --custom ${Cytobands},cytobands,bed --custom ${CustomAnnotationVcf},${CustomAnnotationParameters} --offline --cache --max_af --dir ${Vepcache} && \
    /opt/htslib/bin/bgzip -c ${Name}.annotated.vcf > ${Name}.annotated.vcf.gz && \
    /usr/bin/tabix -p vcf ${Name}.annotated.vcf.gz && \
    /usr/bin/perl -I /opt/lib/perl/VEP/Plugins /opt/vep/ensembl-vep/filter_vep -i ${Name}.annotated.vcf.gz --format vcf -o ${Name}.annotated_filtered.vcf \
    --filter "${default='MAX_AF < 0.001 or not MAX_AF' FilterString}" && \
    /opt/htslib/bin/bgzip -c ${Name}.annotated_filtered.vcf > ${Name}.annotated_filtered.vcf.gz && \
    /usr/bin/tabix -p vcf ${Name}.annotated_filtered.vcf.gz
  }
  runtime {
    docker_image: docker
    cpu: "1"
    memory: "32 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    File annotated_vcf = "${Name}.annotated.vcf.gz"
    File annotated_vcf_index = "${Name}.annotated.vcf.gz.tbi"
    File annotated_filtered_vcf = "${Name}.annotated_filtered.vcf.gz"
    File annotated_filtered_vcf_index = "${Name}.annotated_filtered.vcf.gz.tbi"
  }
}

task annotate_svs {
  String Vcf
  String CNV
  String refFasta
  String refFastaIndex
  String Vepcache
  String Name
  String gender
  String queue
  String jobGroup
  String SVAnnot
  String Translocations
  String Cytobands
  Int? minCNAsize
  Float? minCNAabund
  
  String? tmp
  String docker
  
  command {
    set -eo pipefail && \
    /usr/bin/perl /usr/local/bin/ichorToVCF.pl -g ${gender} -minsize ${minCNAsize} \
    -minabund ${minCNAabund} -r ${refFasta} ${CNV} | /opt/conda/bin/bgzip -c > cnv.vcf.gz && \
    /opt/htslib/bin/tabix -p vcf cnv.vcf.gz && \
    /opt/conda/envs/python2/bin/bcftools query -l cnv.vcf.gz > name.txt && \
    /usr/bin/perl /usr/local/bin/FilterManta.pl -a ${minCNAabund} -r ${refFasta} -k ${Translocations} ${Vcf} filtered.vcf && \
    /opt/conda/envs/python2/bin/svtools afreq filtered.vcf | \
    /opt/conda/envs/python2/bin/svtools vcftobedpe -i stdin | \
    /opt/conda/envs/python2/bin/svtools varlookup -d 200 -c BLACKLIST -a stdin -b ${SVAnnot} | \
    /opt/conda/envs/python2/bin/svtools bedpetovcf | \
    /usr/local/bin/bedtools sort -header -g ${refFastaIndex} -i stdin | /opt/conda/bin/bgzip -c > filtered.tagged.vcf.gz && \
    /opt/conda/envs/python2/bin/bcftools reheader -s name.txt filtered.tagged.vcf.gz > filtered.tagged.reheader.vcf.gz && \
    /opt/htslib/bin/tabix -p vcf filtered.tagged.reheader.vcf.gz && \
    /opt/conda/envs/python2/bin/bcftools concat -a cnv.vcf.gz filtered.tagged.reheader.vcf.gz | \
    /usr/local/bin/bedtools sort -header -g ${refFastaIndex} -i stdin > svs.vcf && \
    /opt/conda/envs/python2/bin/python /usr/local/src/manta/libexec/convertInversion.py /usr/local/bin/samtools ${refFasta} svs.vcf | /opt/conda/bin/bgzip -c > ${Name}.all_svs.vcf.gz && \
    /opt/htslib/bin/tabix -p vcf ${Name}.all_svs.vcf.gz && \
    /opt/conda/envs/python2/bin/bcftools view -O z -i 'KNOWNSV!="." || (FILTER=="PASS" && (BLACKLIST_AF=="." || BLACKLIST_AF==0)) || LOG2RATIO!="."' ${Name}.all_svs.vcf.gz > svs_filtered.vcf.gz && \
    /opt/htslib/bin/tabix -p vcf svs_filtered.vcf.gz && \
    /usr/bin/perl -I /opt/lib/perl/VEP/Plugins /usr/bin/variant_effect_predictor.pl --format vcf --vcf --fasta ${refFasta} --per_gene --symbol --term SO -o ${Name}.svs_annotated.vcf -i svs_filtered.vcf.gz --custom ${Cytobands},cytobands,bed --offline --cache --dir ${Vepcache} && \
    /opt/htslib/bin/bgzip -c ${Name}.svs_annotated.vcf > ${Name}.svs_annotated.vcf.gz && \
    /opt/htslib/bin/tabix -p vcf ${Name}.svs_annotated.vcf.gz
  }
  
  runtime {
    docker_image: docker
    cpu: "1"
    memory: "24 G"
    queue: queue
    job_group: jobGroup
  }
  
  output {
    File vcf = "${Name}.svs_annotated.vcf.gz"
    File vcf_index = "${Name}.svs_annotated.vcf.gz.tbi"
    File allvcf = "${Name}.all_svs.vcf.gz"
    File allvcf_index = "${Name}.all_svs.vcf.gz.tbi"
  }
}

task run_haplotect {
     String Cram
     String CramIndex
     String Bed
     String Name
     String refDict
     String refFasta
     String queue
     String jobGroup

     Int? MinReads

     command <<<
             /usr/bin/awk -v OFS="\t" '{ $2=$2-1; print; }' ${Bed} > /tmp/pos.bed && \
             /usr/local/openjdk-8/bin/java -Xmx6g \
             -jar /opt/hall-lab/gatk-package-4.1.8.1-18-ge2f02f1-SNAPSHOT-local.jar Haplotect \
             -I ${Cram} -R ${refFasta} --sequence-dictionary ${refDict} \
             -mmq 20 -mbq 20 -max-depth-per-sample 10000 -gstol 0.001 -mr ${default=10 MinReads} \
             -htp ${Bed} -L /tmp/pos.bed -outPrefix ${Name}
     >>>

     runtime {
             docker_image: "registry.gsc.wustl.edu/mgi-cle/haplotect:0.3"
             cpu: "1"
             memory: "8 G"
             queue: queue
             job_group: jobGroup
     }
     output {
            File out_file = "${Name}.haplotect.txt"
            File sites_file = "${Name}.haplotectloci.txt"
     }
}

task make_report {
  String SVVCF
  String GeneVCF
  String KnownGenes
  String MappingSummary
  String? CoverageSummary
  String Haplotect
  String SVQC
  String GeneQC
  String Name
  String queue
  String jobGroup
  String tmp
  String docker
  Int? MinReads
  Float? MinVAF
  Int? MinGeneCov
  Int? MinRegionCov
  Int? MinFracCov
  
  command <<<
    cat ${MappingSummary} ${CoverageSummary} | grep SUMMARY | cut -d ',' -f 3,4 | sort -u > qc.txt && \
    /opt/conda/bin/python /usr/local/bin/make_report.py -v ${default="0.05" MinVAF} -r ${default=5 MinReads} -g ${default=30 MinGeneCov} -s ${default=20 MinRegionCov} -f ${default=90 MinFracCov} ${Name} ${GeneVCF} ${SVVCF} ${KnownGenes} "qc.txt" ${GeneQC} ${SVQC} ${Haplotect} > "${Name}.chromoseq.txt"
  >>>
  
  runtime {
    docker_image: docker
    memory: "8 G"
    queue: queue
    job_group: jobGroup
  }
  
  output {
    File report = "${Name}.chromoseq.txt"
  }
}

task gather_files {
  Array[String] OutputFiles
  String OutputDir
  String queue
  String jobGroup
  String docker
  
  command {
    /bin/mv -f -t ${OutputDir}/ ${sep=" " OutputFiles}
  }
  runtime {
    docker_image: "ubuntu:xenial"
    memory: "4 G"
    queue: queue
    job_group: jobGroup
  }
  output {
    String done = stdout()
  }
}

task remove_rundir {
  Array[String] order_by
  String? rundir
  String queue
  String jobGroup
  
  command {
    if [ -n "${rundir}" ]; then 
      /bin/rm -Rf ${rundir}
    fi
  }
  runtime {
    docker_image: "ubuntu:xenial"
    queue: queue
    job_group: jobGroup
  }
  output {
    String done = stdout()
  }
}
