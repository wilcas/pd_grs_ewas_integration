library(data.table)
library(parallel)
library(tidyverse)
library(mice)
# Global data
num_cores <- 32L
setDTthreads(1)
probe_pos <- fread("~/prs_ewas_integration/cis_mQTL_analyses/terre_data/probe_pos.txt")
load("/home1/NEURO/SHARE_DECIPHER/processed_DNAm_data/2022/TERRE_processed_2022/1-TERRE_RG_filtered.RData") # PD_RG_filtered

methy <- minfi::getM(PD_RG_filtered) %>% data.table(keep.rownames = "cpg", key = "cpg")

probe_pos <- probe_pos[geneid %chin% methy$cpg]

argv <- commandArgs(trailingOnly = TRUE)
argv <- list("TERRE_female.covariate", "prs_interaction_result_prsice_female_only.txt.gz", "prsice_female_data/TERRE_female_PRSice.all_score", "Pt_5e-08")
cov_file <- argv[[1]]
outfile <- argv[[2]]
prs_file <- argv[[3]]
prs_thresh <- argv[[4]]
shared_covariates <- fread(cov_file)
env_data <- fread("/home1/NEURO/SHARE_DECIPHER/TERRE_pesticides/pesticides.csv")
mapping <- fread("/home1/NEURO/SHARE_DECIPHER/terre_meta_master.csv")
terre_prs <- fread(prs_file)[, c("FID", "IID", ..prs_thresh)]
colnames(terre_prs) <- c("FID", "IID", "SCORE1_AVG")
mapping$IID <- gsub("_PAE.*", "", mapping$IID)
env_data$num <- mapping$IID[match(env_data$num, mapping$patient)]

pest_missing <- read.csv("/home1/NEURO/SHARE_DECIPHER/TERRE_pesticides/pesticides.csv")
pest_imputed <- read.csv("/home1/NEURO/SHARE_DECIPHER/TERRE_pesticides/pesticides_imputed.csv")

pre_mids <- rbind(cbind(data.frame(X_imputation_ = 0), pest_missing)[, colnames(pest_imputed)], pest_imputed)
pre_mids$num <- as.character(pre_mids$num)
pre_mids <- pre_mids[pre_mids$num %in% mapping$patient & !is.na(mapping$IID[match(pre_mids$num, mapping$patient)]), ]
pest_mids <- suppressWarnings(as.mids(pre_mids, .imp = "X_imputation_", .id = "num"))
envs <- colnames(pest_mids$where)

fit_interaction <- function(rows) {
  tmp_res <- mclapply(
    1:nrow(rows),
    function(i) {
      row <- rows[i, ]
      df <- data.frame(
        y = unlist(methy[row$cpg, -c(1), on = "cpg"])
      )
      covar <- shared_covariates
      env <- row$env
      tmp_df <- complete(pest_mids, action = "long", include = TRUE)[, c(".imp", ".id", env)]
      colnames(tmp_df) <- c(".imp", ".id", "E")
      exposures <- sum(tmp_df$E, na.rm = T) / nrow(tmp_df)
      if (exposures > 0.99 | exposures < 0.01) {
        return(data.frame())
      }
      ix <- match(mapping$IID[match(pre_mids$num, mapping$patient)], terre_prs$IID)
      tmp_df <- cbind(tmp_df, covar[ix, ], y = df$y[ix])
      tmp_df$G <- terre_prs$SCORE1_AVG[ix]
      tmp_df$GxE <- tmp_df$G * tmp_df$E
      df_mids <- suppressWarnings(as.mids(tmp_df))
      if (grepl("male", outfile)) {
        fit <- with(df_mids, lm(y ~ G + E + GxE + V3 + V4 + V5 + age + PC1 + PC2 + PC3 + PC4 + PC5 + PC6 + PC7 + PC8 + PC9 + PC10))
      } else {
        fit <- with(df_mids, lm(y ~ G + E + GxE + V3 + V4 + V5 + age + sex + PC1 + PC2 + PC3 + PC4 + PC5 + PC6 + PC7 + PC8 + PC9 + PC10))
      }
      stats <- summary(pool(fit)) %>%
        select(-df) %>%
        column_to_rownames(var = "term")
      G <- stats["G", ]
      E <- stats["E", ]
      GxE <- stats["GxE", ]
      names(G) <- paste0("G", c("est", "se", "t", "p"))
      names(E) <- paste0("E", c("est", "se", "t", "p"))
      names(GxE) <- paste0("GxE", c("est", "se", "t", "p"))
      res <- data.frame(c(row, G, E, GxE))
      return(res)
    },
    mc.cores = num_cores
  )
  return(rbindlist(tmp_res))
}
load("~/prs_ewas_integration/prs_analyses/prs_nalls_cross_w_sex_stratified.RData")
manifest <- expand_grid(cpg = probe_pos$gene, env = envs)
just_hits <- top_prs_hits[top_prs_hits$adj.P.Val < 0.25, ]$ID
system.time(results <- fit_interaction(manifest[manifest$cpg %in% just_hits, ]))

fwrite(results, outfile, sep = "\t", row.names = F, quote = F)
