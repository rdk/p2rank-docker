// P2Rank — predict ligand binding sites for a channel of structures.
//
// Include it as:
//
//     include { P2RANK } from './modules/p2rank/main.nf'
//     P2RANK(structure_ch)   // channel of path(mmCIF/PDB)
//
// and give the process a container via the 'p2rank' label. Requires these
// params (see README, "Nextflow"):
//
//     params.outdir             where pockets.csv is published
//     params.p2rank_config      P2Rank config: 'default', 'alphafold', ...
//     params.p2rank_batch_size  structures per prank call
//
// Emits one pockets.csv for the run: every structure's predictions, with a
// 'structure' column prepended.

process RUN_P2RANK {

    label 'p2rank'
    errorStrategy 'ignore'

    input:
    path structures

    output:
    path "out/*_predictions.csv", emit: predictions
    path "out/*_residues.csv",    emit: residues

    script:
    """
    printf '%s\\n' ${structures} > batch.ds

    prank predict batch.ds \\
        -o out \\
        -c ${params.p2rank_config} \\
        -threads ${task.cpus}
    """
}

process MERGE_P2RANK {

    label 'p2rank'
    publishDir params.outdir, mode: 'copy', overwrite: true

    input:
    path csvs

    output:
    path 'pockets.csv'

    script:
    """
    # The image ships a JRE, not Python: keep the merge to awk.
    awk 'FNR==1 {
             structure = FILENAME
             sub(/_predictions\\.csv\$/, "", structure)
             if (!header++) { print "structure," \$0 }
             next
         }
         NF { print structure "," \$0 }' *_predictions.csv \\
      | sed 's/ *, */,/g' > pockets.csv
    """
}

workflow P2RANK {
    take:
    structure_ch // expects: path(mmCIF/PDB file)

    main:
    RUN_P2RANK(structure_ch.collate(params.p2rank_batch_size.toInteger()))
    MERGE_P2RANK(RUN_P2RANK.out.predictions.collect())

    emit:
    MERGE_P2RANK.out
}
