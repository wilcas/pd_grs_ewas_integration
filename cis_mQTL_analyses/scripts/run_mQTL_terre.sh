#!/bin/bash
/usr/local/R-3.6.2/bin/Rscript run_matrixEQTL.R --data_dir="terre_data/" \
	--SNP_fname="all_imputed_matrixeQTL.txt" \
	--cov_file="covariates_9_methy_PC.txt" \
	--cis_outfile="cis_all_impute_mQTL_results_9_methy_PC.txt" \
	--snp_pos="snp_pos.txt" \
	--methylation_fname="methylation_combat.txt" \
	--probe_pos="probe_pos.txt"

pigz terre_data/cis_all_impute_mQTL_results_9_methy_PC.txt
