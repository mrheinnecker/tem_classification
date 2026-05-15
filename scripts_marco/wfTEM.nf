params.dryrun="FALSE"

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
    path rawdir
    path pngdir
    val dryrun

    output:
    path "images_to_process.csv", emit: to_process
    path "manually_filled_log.tsv"
    path "TEM_screen_image_count.pdf"
    
    script:
    """
    Rscript /g/schwab/marco/repos/tem_classification/scripts_marco/imaging_ov.R -r "${params.rawdir}" -p $pngdir -d $dryrun
    
    """  
}



process RENAME {
  
    cpus   = 1
    memory = "2GB"
    time   = "0.25h"    
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'  
    input:
    tuple val(filename), path(raw_mrc), path(mdoc_file), val(shortname), val(req_mem)
    
    output:
    tuple val(filename), path("*.mrc"), path("*.mdoc"), emit: renamed_mrc
    
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
    tuple val(filename), path(raw_mrc), path(raw_mdoc)
    
    output:
    tuple val(filename), path("*_blend.mrc"), path("*.pl"),  path(raw_mrc), emit: justblend_tup
    
    script:
    """
    export IMOD_DIR=/g/easybuild/x86_64/Rocky/8/haswell/software/IMOD/5.1.0-foss-2023a-CUDA-12.1.1
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
    tuple val(filename), path(blend_mrc), path(blend_pl), path(raw_mrc)
    
    output:
    tuple val(filename), path("*correctionblend.mrc"), emit: correctionblend_tup
    
    script:
    """
    echo "${raw_mrc}"

    export IMOD_DIR=/g/easybuild/x86_64/Rocky/8/haswell/software/IMOD/5.1.0-foss-2023a-CUDA-12.1.1
    export AUTODOC_DIR=\$IMOD_DIR/autodoc
    export PATH=\$IMOD_DIR/bin:\$PATH

    blendmont -imi "${raw_mrc}" -pli "${blend_pl}" -imo "${raw_mrc.baseName}_correctionblend.mrc" -int 2 -roo test1 -sloppy -sum

    """  
}



process EXPORTOVPNG {
  
    cpus   = 1
    memory = "128GB"
    time   = "0.2h"    
  
    //publishDir "${params.pngdir}", mode:'copy'
    publishDir { 
    def m = (blend_mrc.baseName =~ /_(NAP|BAR|KRI|POR|TAL|ATH|BIL)_/)
    def sample = m ? m[0][1] : "UNKNOWN"
    "${params.pngdir}/${sample}"
    }, mode: 'copy'
    
    containerOptions '--bind /g --bind /home --bind /scratch'

    input:
    //tuple val(filename), path(blend_mrc)
    path blend_mrc

    output:
    path "*.png", emit: png_ov
    
    script:
    """

      python3 /g/schwab/marco/repos/tem_classification/scripts_marco/process_images.py \
        -i "${blend_mrc}" \
        -o "${blend_mrc.baseName}.png"

    """  
}



process EUBICONVERSION {
  
    cpus   = 1
    memory = "5GB"
    time   = "1h"    
  
    publishDir "${params.outdir}/${filename}", mode:'copy'
    containerOptions '--bind /home --bind /scratch'  
    errorStrategy = 'ignore' 

    input:
    tuple val(filename), path(correctionblend_mrc), path(mdoc_file), path(raw_mdoc)
    
    output:
    tuple val(filename), path(mdoc_file), path("conversion_done.txt"), path("*omezarr"), emit: omezarr_tup
    
    script:
    """
    eubi to_zarr \
      /scratch/rheinnec/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1_correctionblend.mrc \
      /scratch/rheinnec/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1_correctionblend_omezarr5 \
      --x_unit nm \
      --y_unit nm \
      --x_scale 1.766 \
      --y_scale 1.766

    touch conversion_done.txt


    """  
}





workflow {
  

  Channel
    .from(params.dryrun)
    .set { dryrun_ch }


  Channel
    .fromPath(params.rawdir)
    .collect()
    .set { rawdir_ch }

  Channel
    .fromPath(params.pngdir)
    .collect()
    .set { pngdir_ch }

  CHECKNEWIMAGES(rawdir_ch, pngdir_ch, dryrun_ch)

  Channel
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


  ch_a_second = JUSTBLEND.out.justblend_tup.map { t -> t[1] }
  ch_b_second = CORRECTIONBLEND.out.correctionblend_tup.map { t -> t[1] }

  combined_ch = ch_a_second.mix(ch_b_second)


  EXPORTOVPNG(
    ch_b_second
  )

}






