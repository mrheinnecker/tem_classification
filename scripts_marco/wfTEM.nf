

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


process JUSTBLEND {
  
    cpus   = 1
    memory = "2GB"
    time   = "1h"    
  
    publishDir "${params.logdir}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'  
    input:
    path raw_mrc
    
    output:
    path "*_blend.mrc", emit: blend_mrc
    
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
    memory = "2GB"
    time   = "1h"    
  
    publishDir "${params.logdir}", mode:'copy'
    containerOptions '--bind /home --bind /scratch'  
    input:
    path raw_mrc
    path raw_pl
    
    output:
    path "*correctionblend.mrc", emit: blend_mrc
    
    script:
    """
    echo "${raw_mrc}"

    export IMOD_DIR=/g/easybuild/x86_64/Rocky/8/haswell/software/IMOD/5.1.0-foss-2023a-CUDA-12.1.1
    export AUTODOC_DIR=\$IMOD_DIR/autodoc
    export PATH=\$IMOD_DIR/bin:\$PATH

    blendmont -imi "${raw_mrc}" -pli "${raw_pl}" -imo "${raw_mrc.baseName}_correctionblend.mrc" -int 1 -roo test1 -sloppy

    """  
}



process EXPORTOVPNG {
  
    cpus   = 1
    memory = "5GB"
    time   = "1h"    
  
    publishDir "${params.logdir}", mode:'copy'
    containerOptions '--bind /g --bind /home --bind /scratch'

    input:
    path blend_mrc
    
    output:
    path "*.png", emit: png_ov
    
    script:
    """
      python3 /g/schwab/marco/repos/tem_classification/scripts_marco/process_images.py \
        -i "${blend_mrc}" \
        -o "${blend_mrc.baseName}_ov.png"

    """  
}



workflow {
  


  Channel
    .fromPath(params.raw_mrc)
    .collect()
    .set { raw_mrc_ch }

  Channel
    .fromPath(params.raw_pl)
    .collect()
    .set { raw_pl_ch }


  JUSTBLEND(
    raw_mrc_ch
  )

  CORRECTIONBLEND(
    raw_mrc_ch,
    raw_pl_ch
  )

  blend_png_ch=CORRECTIONBLEND.out.blend_mrc.concat(JUSTBLEND.out.blend_mrc)

  blend_png_ch.view()

  EXPORTOVPNG(
    blend_png_ch
  )
}






