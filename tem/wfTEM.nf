params.dryrun = params.dryrun ?: "FALSE"
params.script_dir = params.script_dir ?: baseDir.toString()
params.sheet_mode = params.sheet_mode ?: "local"
params.sheet_url = params.sheet_url ?: "https://docs.google.com/spreadsheets/d/143uVeeJ72SQE5eK01lzWYCEiT7pJUF3lX7hJl3R9s9I/edit?gid=258669282#gid=258669282"
params.collection_table_url = params.collection_table_url ?: "https://docs.google.com/spreadsheets/d/15WNNnse7OvlfiJwFOFYbQA4zIp-5nKc0icRZYfJS--o/edit?gid=1643802951#gid=1643802951"
params.google_key = params.google_key ?: "${params.script_dir}/trec-tem-screen-e98a2e03f58b.json"
params.local_log = params.local_log ?: "${params.outdir}/image_log_local.tsv"
params.workflow_stage = params.workflow_stage ?: "all"
params.imod_dir = params.imod_dir ?: "/g/easybuild/x86_64/Rocky/8/haswell/software/IMOD/5.1.0-foss-2023a-CUDA-12.1.1"
params.s3_bucket = params.s3_bucket ?: "s3embl/temscreen"
params.zarr_format = params.zarr_format ?: 2
params.pixel_scale_x = params.pixel_scale_x ?: 1.766
params.pixel_scale_y = params.pixel_scale_y ?: 1.766
params.gradient_mode = params.gradient_mode ?: "auto"
params.gradient_threshold = params.gradient_threshold ?: 0.18
params.gradient_downsample = params.gradient_downsample ?: 16
params.gradient_background_sigma = params.gradient_background_sigma ?: 20
params.gradient_chunk_rows = params.gradient_chunk_rows ?: 2048

// process EXTRACTFEATURES {
  
//     cpus   = 1
//     memory = "25GB"
//     time   = "1h"
     
//     errorStrategy = 'ignore' 
  
//     publishDir "${params.logdir}/$pid", mode:'copy'
  
//     input:
//     val pid
//     path final_analysis_fncts
//     path common_reoccurring_fncts
//     path global_wf_fncts
//     path r_profile
//     path weekly_fncts
//     path diff_feature_fncts
//     path qc_data_fncts
//     path file_gene_model
//     path pre_proc_fncts
//     path file_sel_fncts
//     path am_file
//     path am_frameshift_file
//     path precalc_cutoffs
//     path final_models_dir
//     path am_fncts
//     path main_script
    
//     output:
//     tuple val(pid), path("*"), emit: features
    
//     script:
//     """
    
    
//     Rscript ${main_script} \
//       --r_profile $r_profile \
//       --final_analysis_fncts $final_analysis_fncts \
//       --global_wf_fncts $global_wf_fncts \
//       --ml_model_fncts $weekly_fncts \
//       --diff_feature_fncts $diff_feature_fncts \
//       --qcpodest_functions $qc_data_fncts \
//       --common_reoccurring $common_reoccurring_fncts \
//       --file_gene_model $file_gene_model \
//       --pre_proc_fncts $pre_proc_fncts \
//       --file_sel_fncts $file_sel_fncts \
//       --aplhaMissense_scores $am_file \
//       --am_frameshift_raw $am_frameshift_file \
//       --precalc_cutoffs $precalc_cutoffs \
//       --final_models_dir $final_models_dir \
//       --poi "${pid}" \
//       --functional_impact_filtering "author" \
//       --am_fncts $am_fncts

    
//     """
    
      
  
// }

process CHECKNEWIMAGES {
  
    cpus   = 1
    memory = "1GB"
    time   = "1h"    
  
    publishDir "${params.logdir}", mode:'copy'
    containerOptions '--bind /g --bind /scratch'  

    input:
    val rawdir
    val pngdir
    val dryrun
    val script_dir
    val sheet_mode
    val sheet_url
    val google_key
    val local_log

    output:
    path "images_to_process.csv", emit: to_process
    path "manually_filled_log*"
    path "TEM_screen_image_count.pdf"
    path "TEM_screen_image_count.png"
    path "all_datasets.tsv"
    
    script:
    """
    Rscript "${script_dir}/imaging_ov.R" \
      --rawdir "${rawdir}" \
      --pngdir "${pngdir}" \
      --dryrun "${dryrun}" \
      --script_dir "${script_dir}" \
      --sheet_mode "${sheet_mode}" \
      --sheet_url "${sheet_url}" \
      --google_key "${google_key}" \
      --local_log "${local_log}"
    
    """  
}



process RENAME {
  
    cpus   = 1
    memory { "${Math.min(Math.max((req_mem as Integer), 4), 32)}GB" }
    time   = "0.25h"    
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'  
    input:
    tuple val(filename), path(raw_mrc), path(mdoc_file), val(shortname), val(req_mem)
    
    output:
    tuple val(filename), path("*.mrc"), path("*.mdoc"), val(req_mem), emit: renamed_mrc
    
    script:
    """
    cp $raw_mrc "./${filename}.mrc"
    cp $mdoc_file "./${filename}.mrc.mdoc"
    
    """  
}

process JUSTBLEND {
  
    cpus   = 1
    memory = "2GB"
    time   = "1h"    
  
    errorStrategy 'retry'
    maxRetries 1
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'  
    input:
    tuple val(filename), path(raw_mrc), path(raw_mdoc), val(req_mem)
    
    output:
    tuple val(filename), path("*_blend.mrc"), path("*.pl"),  path(raw_mrc), val(req_mem), emit: justblend_tup
    
    script:
    """
    export IMOD_DIR="${params.imod_dir}"
    export AUTODOC_DIR=\$IMOD_DIR/autodoc
    export PATH=\$IMOD_DIR/bin:\$PATH
    justblend $raw_mrc
    
    
    """  
}

process CORRECTIONBLEND {
  
    cpus   = 1
    memory = "5GB"
    time   = "1h"    
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /home --bind /scratch'  
    errorStrategy = 'ignore' 

    input:
    tuple val(filename), path(blend_mrc), path(blend_pl), path(raw_mrc), val(req_mem)
    
    output:
    tuple val(filename), path("*correctionblend.mrc"), val(req_mem), emit: correctionblend_tup
    
    script:
    """
    echo "${raw_mrc}"

    export IMOD_DIR="${params.imod_dir}"
    export AUTODOC_DIR=\$IMOD_DIR/autodoc
    export PATH=\$IMOD_DIR/bin:\$PATH

    blendmont -imi "${raw_mrc}" -pli "${blend_pl}" -imo "${raw_mrc.baseName}_correctionblend.mrc" -int 2 -roo test1 -sloppy -sum

    """  
}



process EXPORTOVPNG {
  
    cpus   = 1
    memory { "${Math.min(Math.max((req_mem as Integer), 16), 96)}GB" }
    time   = "1h"    
  
    //publishDir "${params.pngdir}", mode:'copy'
    publishDir { 
    def m = (correctionblend_mrc.baseName =~ /_(NAP|BAR|KRI|POR|TAL|ATH|BIL)_/)
    def sample = m ? m[0][1] : "UNKNOWN"
    "${params.pngdir}/${sample}"
    }, mode: 'copy', pattern: "*.png"
    containerOptions '--bind /g --bind /home --bind /scratch'

    input:
    tuple val(filename), path(correctionblend_mrc), val(req_mem)

    output:
    path "*.png", emit: png_ov
    
    script:
    """

      echo "exporting overview png"

      python3 "${params.script_dir}/process_images.py" \
        -i "${correctionblend_mrc}" \
        -o "${correctionblend_mrc.baseName}.png" \
        --qc-output "${correctionblend_mrc.baseName}_coarse_mask_qc.png" \
        --foreground "darker" \
        --threshold "otsu" \
        --sigma 5 \
        --padding 1000 \
        --mask-dilation-fraction 0.2 \
        --min-object-size 50000 \
        --threshold-scale 1

    """  
}


process CORRECTGRADIENT {
  
    cpus   = 1
    memory { "${Math.min(Math.max((req_mem as Integer), 16), 96)}GB" }
    time   = "1h"    
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'
    errorStrategy = 'ignore' 

    input:
    tuple val(filename), path(correctionblend_mrc), val(req_mem)
    
    output:
    tuple val(filename), path("*_gradientcorrected.mrc"), val(req_mem), emit: corrected_mrc_tup
    path "*_gradient_qc.png", emit: gradient_qc
    path "*_gradient_metrics.tsv", emit: gradient_metrics
    
    script:
    """
      python3 "${params.script_dir}/correct_gradient.py" \
        --input "${correctionblend_mrc}" \
        --output "${correctionblend_mrc.baseName}_gradientcorrected.mrc" \
        --qc-png "${correctionblend_mrc.baseName}_gradient_qc.png" \
        --metrics "${correctionblend_mrc.baseName}_gradient_metrics.tsv" \
        --mode "${params.gradient_mode}" \
        --threshold "${params.gradient_threshold}" \
        --downsample "${params.gradient_downsample}" \
        --background-sigma "${params.gradient_background_sigma}" \
        --chunk-rows "${params.gradient_chunk_rows}"
    """  
}


process EXTRACTIMAGESTATS {
  
    cpus   = 1
    memory = "32GB"
    time   = "10m"    
  
    publishDir "${params.logdir}/image_stats", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'

    input:
    tuple val(filename), path(correctionblend_mrc), val(req_mem)
    
    output:
    path "*_image_stats.tsv", emit: image_stats
    
    script:
    """
      python3 "${params.script_dir}/extract_image_stats.py" \
        --input "${correctionblend_mrc}" \
        --name "${filename}" \
        --output "${filename}_image_stats.tsv"
    """  
}



process EUBICONVERSION {
  
    cpus   = 1
    memory { "${Math.min(Math.max((req_mem as Integer) * 2, 32), 128)}GB" }
    time   = "1h"    
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'
    errorStrategy = 'ignore' 

    input:
    tuple val(filename), path(correctionblend_mrc), val(req_mem)
    
    output:
    tuple val(filename), path("*omezarr"), emit: omezarr_tup
    path "conversion_done.txt"
    
    script:
    """
    eubi to_zarr \
      "${correctionblend_mrc}" \
      "${filename}_omezarr" \
      --x_unit nm \
      --y_unit nm \
      --x_scale "${params.pixel_scale_x}" \
      --y_scale "${params.pixel_scale_y}" \
      --dimension_order xyzct \
      --squeeze True \
      --save_omexml True \
      --zar_format "${params.zarr_format}" \
      --auto_chunk True \
      --jvm_memory 8GB \
      --max_workers 1
      
    ##       --metadata_reader bioio this flag causes the error  

    touch conversion_done.txt


    """  
}


process S3UPLOAD {


    cpus 1
    memory "1 GB"
    time "10m"

    input:
    tuple val(filename), path(omezarr)

    output:
    path "done.txt"

    /*
     * Optional:
     * use this if your cluster needs bind mounts explicitly
     */
    containerOptions "--bind /g --bind /scratch --bind /home"

    script:
    """

    echo "Uploading file...."

    image_zarr="$omezarr"
    image_target_name="\$(basename "\$image_zarr")"

    if [ ! -e "\$image_zarr/.zattrs" ] && [ ! -e "\$image_zarr/.zgroup" ]; then
      inner_zarr="\$(find "\$image_zarr" -mindepth 1 -maxdepth 3 -type d \\( -name '*.zarr' -o -name '*.ome.zarr' \\) | head -n 1)"
      if [ -n "\$inner_zarr" ]; then
        image_zarr="\$inner_zarr"
        image_target_name="\$(basename "\$inner_zarr")"
      fi
    fi

    mc cp "\$image_zarr/" "${params.s3_bucket}/" -r

    echo "Done."
    
    touch done.txt
    
    """
}


process COLLECTS3FILES {


    cpus 1
    memory "1 GB"
    time "10m"

    input:
    tuple path(done)

    output:
    path "all_s3_entries.txt", emit: all_s3

    /*
     * Optional:
     * use this if your cluster needs bind mounts explicitly
     */
    containerOptions "--bind /g --bind /scratch --bind /home"

    script:
    """

    mc ls "${params.s3_bucket}" > "all_s3_entries.txt"

    
    """
}


process MAKECOLLECTIONTABLE {


    cpus 1
    memory "1 GB"
    time "10m"

    input:
    path all_s3
    path image_stats

    output:
    path "done.tsv"

    /*
     * Optional:
     * use this if your cluster needs bind mounts explicitly
     */
    containerOptions "--bind /g --bind /scratch --bind /home"

    script:
    """

    Rscript "${params.script_dir}/make_collection_table.R" \
      --all_s3 "$all_s3" \
      --image_stats_dir "." \
      --sheet_mode "${params.sheet_mode}" \
      --google_key "${params.google_key}" \
      --collection_table_url "${params.collection_table_url}" \
      --local_collection_table "collection_table.tsv" \
      --image_log_url "${params.sheet_url}" \
      --image_log_sheet "${params.dryrun.toString().toBoolean() ? 'image_log_test' : 'image_log'}" \
      --local_image_log "${params.local_log}"

    
    """
}


workflow {
  

  CHECKNEWIMAGES(
    params.rawdir,
    params.pngdir,
    params.dryrun,
    params.script_dir,
    params.sheet_mode,
    params.sheet_url,
    params.google_key,
    params.local_log
  )

  if (params.workflow_stage != "discover") {

    CHECKNEWIMAGES.out.to_process
        .splitCsv(header:true)
        .map { row -> tuple row.filename, row.file, row.mdoc_file, row.shortname, row.req_mem}  
        .set { batch_ch }

    RENAME(batch_ch)

    JUSTBLEND(
      RENAME.out.renamed_mrc
    )


    CORRECTIONBLEND(
      JUSTBLEND.out.justblend_tup
    )

    CORRECTGRADIENT(
      CORRECTIONBLEND.out.correctionblend_tup
    )

    EXTRACTIMAGESTATS(
      CORRECTGRADIENT.out.corrected_mrc_tup
    )

    ch_a_second = JUSTBLEND.out.justblend_tup.map { t -> t[1] }
    ch_b_second = CORRECTGRADIENT.out.corrected_mrc_tup.map { t -> t[1] }

    combined_ch = ch_a_second.mix(ch_b_second)


    EXPORTOVPNG(
      CORRECTGRADIENT.out.corrected_mrc_tup
    )

    EUBICONVERSION(
      CORRECTGRADIENT.out.corrected_mrc_tup
    )

    if (params.workflow_stage == "all") {
      upload_ch = EUBICONVERSION.out.omezarr_tup

      s3upload_out_ch=S3UPLOAD(
        upload_ch
      )

      fully_done_ch=s3upload_out_ch.collect()

      COLLECTS3FILES(
        fully_done_ch
      )

      image_stats_ch = EXTRACTIMAGESTATS.out.image_stats.collect()

      MAKECOLLECTIONTABLE(
        COLLECTS3FILES.out.all_s3,
        image_stats_ch
      )
    }
  }


}






