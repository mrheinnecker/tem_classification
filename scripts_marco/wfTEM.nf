

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
    memory = "5GB"
    time   = "1h"    
  
    publishDir "${params.logdir}", mode:'copy'
  
    input:
    path raw_mrc
    
    output:
    path "*_blend.mrc", emit: justblend_mrc
    
    script:
    """

    module load IMOD

    justblend $raw_mrc
    
    """  
}

process CORRECTIONBLEND {
  
    cpus   = 1
    memory = "5GB"
    time   = "1h"    
  
    publishDir "${params.logdir}", mode:'copy'
  
    input:
    path raw_mrc
    path raw_pl
    
    output:
    path "*_blend.mrc", emit: justblend_mrc
    
    script:
    """
    echo "${raw_mrc}"

    module load IMOD

    blendmont -imi "${raw_mrc}" -pli "${raw_pl}" -imo "test_blend.mrc" -int 1 -roo test1 -sloppy

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


}






