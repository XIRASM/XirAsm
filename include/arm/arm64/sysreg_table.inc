// A64 system-instruction register encodings (M6) - GENERATED, do not edit.
//
// Source of truth: LLVM AArch64SystemOperands.td (TLBI/DC/AT/IC class
// entries plus the ROSysReg/RWSysReg core registers). Extracted
// mechanically by an awk script over the TableGen source.
// Each constant packs the 16-bit SysReg encoding for arm64_msr_sys /
// arm64_mrs_sys: op0(15-14) op1(13-11) CRn(10-7) CRm(6-3) op2(2-0), with
// op0 = 0b01 for the TLBI/DC/AT/IC space. Field values are recorded in
// the comment above each constant; reg= gives the Rt-use policy
// (REQUIRED = Rt needed, OPTIONAL = Rt may be XZR, NONE = no Rt).

// Core read/write registers (LLVM ROSysReg/RWSysReg defs):
// op0=3 op1=0 crn=0 crm=0 op2=0 (RO)
const arm64_sys_midr_el1: u64 = 49152
// op0=3 op1=3 crn=0 crm=0 op2=1 (RO)
const arm64_sys_ctr_el0: u64 = 55297
// op0=3 op1=0 crn=1 crm=0 op2=0 (RW)
const arm64_sys_sctlr_el1: u64 = 49280
// op0=3 op1=3 crn=14 crm=0 op2=1 (RO)
const arm64_sys_cntpct_el0: u64 = 57089
// op0=1 op1=0 crn=7 crm=8 op2=0
const arm64_sys_at_s1e1r: u64 = 17344
// op0=1 op1=4 crn=7 crm=8 op2=0
const arm64_sys_at_s1e2r: u64 = 25536
// op0=1 op1=6 crn=7 crm=8 op2=0
const arm64_sys_at_s1e3r: u64 = 29632
// op0=1 op1=0 crn=7 crm=8 op2=1
const arm64_sys_at_s1e1w: u64 = 17345
// op0=1 op1=4 crn=7 crm=8 op2=1
const arm64_sys_at_s1e2w: u64 = 25537
// op0=1 op1=6 crn=7 crm=8 op2=1
const arm64_sys_at_s1e3w: u64 = 29633
// op0=1 op1=0 crn=7 crm=8 op2=2
const arm64_sys_at_s1e0r: u64 = 17346
// op0=1 op1=0 crn=7 crm=8 op2=3
const arm64_sys_at_s1e0w: u64 = 17347
// op0=1 op1=4 crn=7 crm=8 op2=4
const arm64_sys_at_s12e1r: u64 = 25540
// op0=1 op1=4 crn=7 crm=8 op2=5
const arm64_sys_at_s12e1w: u64 = 25541
// op0=1 op1=4 crn=7 crm=8 op2=6
const arm64_sys_at_s12e0r: u64 = 25542
// op0=1 op1=4 crn=7 crm=8 op2=7
const arm64_sys_at_s12e0w: u64 = 25543
// op0=1 op1=0 crn=7 crm=9 op2=0
const arm64_sys_at_s1e1rp: u64 = 17352
// op0=1 op1=0 crn=7 crm=9 op2=1
const arm64_sys_at_s1e1wp: u64 = 17353
// op0=1 op1=0 crn=7 crm=9 op2=2
const arm64_sys_at_s1e1a: u64 = 17354
// op0=1 op1=4 crn=7 crm=9 op2=2
const arm64_sys_at_s1e2a: u64 = 25546
// op0=1 op1=6 crn=7 crm=9 op2=2
const arm64_sys_at_s1e3a: u64 = 29642
// op0=1 op1=3 crn=7 crm=4 op2=1
const arm64_sys_dc_zva: u64 = 23457
// op0=1 op1=0 crn=7 crm=6 op2=1
const arm64_sys_dc_ivac: u64 = 17329
// op0=1 op1=0 crn=7 crm=6 op2=2
const arm64_sys_dc_isw: u64 = 17330
// op0=1 op1=3 crn=7 crm=10 op2=1
const arm64_sys_dc_cvac: u64 = 23505
// op0=1 op1=0 crn=7 crm=10 op2=2
const arm64_sys_dc_csw: u64 = 17362
// op0=1 op1=3 crn=7 crm=11 op2=1
const arm64_sys_dc_cvau: u64 = 23513
// op0=1 op1=3 crn=7 crm=14 op2=1
const arm64_sys_dc_civac: u64 = 23537
// op0=1 op1=0 crn=7 crm=14 op2=2
const arm64_sys_dc_cisw: u64 = 17394
// op0=1 op1=3 crn=7 crm=12 op2=1
const arm64_sys_dc_cvap: u64 = 23521
// op0=1 op1=3 crn=7 crm=13 op2=1
const arm64_sys_dc_cvadp: u64 = 23529
// op0=1 op1=0 crn=7 crm=6 op2=3
const arm64_sys_dc_igvac: u64 = 17331
// op0=1 op1=0 crn=7 crm=6 op2=4
const arm64_sys_dc_igsw: u64 = 17332
// op0=1 op1=0 crn=7 crm=10 op2=4
const arm64_sys_dc_cgsw: u64 = 17364
// op0=1 op1=0 crn=7 crm=14 op2=4
const arm64_sys_dc_cigsw: u64 = 17396
// op0=1 op1=3 crn=7 crm=10 op2=3
const arm64_sys_dc_cgvac: u64 = 23507
// op0=1 op1=3 crn=7 crm=12 op2=3
const arm64_sys_dc_cgvap: u64 = 23523
// op0=1 op1=3 crn=7 crm=13 op2=3
const arm64_sys_dc_cgvadp: u64 = 23531
// op0=1 op1=3 crn=7 crm=14 op2=3
const arm64_sys_dc_cigvac: u64 = 23539
// op0=1 op1=3 crn=7 crm=4 op2=3
const arm64_sys_dc_gva: u64 = 23459
// op0=1 op1=0 crn=7 crm=6 op2=5
const arm64_sys_dc_igdvac: u64 = 17333
// op0=1 op1=0 crn=7 crm=6 op2=6
const arm64_sys_dc_igdsw: u64 = 17334
// op0=1 op1=0 crn=7 crm=10 op2=6
const arm64_sys_dc_cgdsw: u64 = 17366
// op0=1 op1=0 crn=7 crm=14 op2=6
const arm64_sys_dc_cigdsw: u64 = 17398
// op0=1 op1=3 crn=7 crm=10 op2=5
const arm64_sys_dc_cgdvac: u64 = 23509
// op0=1 op1=3 crn=7 crm=12 op2=5
const arm64_sys_dc_cgdvap: u64 = 23525
// op0=1 op1=3 crn=7 crm=13 op2=5
const arm64_sys_dc_cgdvadp: u64 = 23533
// op0=1 op1=3 crn=7 crm=14 op2=5
const arm64_sys_dc_cigdvac: u64 = 23541
// op0=1 op1=3 crn=7 crm=4 op2=4
const arm64_sys_dc_gzva: u64 = 23460
// op0=1 op1=3 crn=7 crm=4 op2=5
const arm64_sys_dc_zgbva: u64 = 23461
// op0=1 op1=3 crn=7 crm=4 op2=7
const arm64_sys_dc_gbva: u64 = 23463
// op0=1 op1=4 crn=7 crm=14 op2=0
const arm64_sys_dc_cipae: u64 = 25584
// op0=1 op1=4 crn=7 crm=14 op2=7
const arm64_sys_dc_cigdpae: u64 = 25591
// op0=1 op1=6 crn=7 crm=14 op2=5
const arm64_sys_dc_cigdpapa: u64 = 29685
// op0=1 op1=6 crn=7 crm=14 op2=1
const arm64_sys_dc_cipapa: u64 = 29681
// op0=1 op1=3 crn=7 crm=15 op2=0
const arm64_sys_dc_civaoc: u64 = 23544
// op0=1 op1=3 crn=7 crm=11 op2=0
const arm64_sys_dc_cvaoc: u64 = 23512
// op0=1 op1=3 crn=7 crm=15 op2=7
const arm64_sys_dc_cigdvaoc: u64 = 23551
// op0=1 op1=3 crn=7 crm=11 op2=7
const arm64_sys_dc_cgdvaoc: u64 = 23519
// op0=1 op1=0 crn=7 crm=1 op2=0
const arm64_sys_ic_ialluis: u64 = 17288
// op0=1 op1=0 crn=7 crm=5 op2=0
const arm64_sys_ic_iallu: u64 = 17320
// op0=1 op1=3 crn=7 crm=5 op2=1
const arm64_sys_ic_ivau: u64 = 23465
// op0=1 op1=4 crn=8 crm=0 op2=1 reg=REQUIRED
const arm64_sys_tlbi_ipas2e1is: u64 = 25601
// op0=1 op1=4 crn=8 crm=0 op2=5 reg=REQUIRED
const arm64_sys_tlbi_ipas2le1is: u64 = 25605
// op0=1 op1=0 crn=8 crm=3 op2=0 reg=OPTIONAL
const arm64_sys_tlbi_vmalle1is: u64 = 17432
// op0=1 op1=4 crn=8 crm=3 op2=0 reg=OPTIONAL
const arm64_sys_tlbi_alle2is: u64 = 25624
// op0=1 op1=6 crn=8 crm=3 op2=0 reg=OPTIONAL
const arm64_sys_tlbi_alle3is: u64 = 29720
// op0=1 op1=0 crn=8 crm=3 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae1is: u64 = 17433
// op0=1 op1=4 crn=8 crm=3 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae2is: u64 = 25625
// op0=1 op1=6 crn=8 crm=3 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae3is: u64 = 29721
// op0=1 op1=0 crn=8 crm=3 op2=2 reg=REQUIRED
const arm64_sys_tlbi_aside1is: u64 = 17434
// op0=1 op1=0 crn=8 crm=3 op2=3 reg=REQUIRED
const arm64_sys_tlbi_vaae1is: u64 = 17435
// op0=1 op1=4 crn=8 crm=3 op2=4 reg=OPTIONAL
const arm64_sys_tlbi_alle1is: u64 = 25628
// op0=1 op1=0 crn=8 crm=3 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale1is: u64 = 17437
// op0=1 op1=4 crn=8 crm=3 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale2is: u64 = 25629
// op0=1 op1=6 crn=8 crm=3 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale3is: u64 = 29725
// op0=1 op1=4 crn=8 crm=3 op2=6 reg=OPTIONAL
const arm64_sys_tlbi_vmalls12e1is: u64 = 25630
// op0=1 op1=0 crn=8 crm=3 op2=7 reg=REQUIRED
const arm64_sys_tlbi_vaale1is: u64 = 17439
// op0=1 op1=4 crn=8 crm=4 op2=1 reg=REQUIRED
const arm64_sys_tlbi_ipas2e1: u64 = 25633
// op0=1 op1=4 crn=8 crm=4 op2=5 reg=REQUIRED
const arm64_sys_tlbi_ipas2le1: u64 = 25637
// op0=1 op1=0 crn=8 crm=7 op2=0 reg=NONE
const arm64_sys_tlbi_vmalle1: u64 = 17464
// op0=1 op1=4 crn=8 crm=7 op2=0 reg=NONE
const arm64_sys_tlbi_alle2: u64 = 25656
// op0=1 op1=6 crn=8 crm=7 op2=0 reg=NONE
const arm64_sys_tlbi_alle3: u64 = 29752
// op0=1 op1=0 crn=8 crm=7 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae1: u64 = 17465
// op0=1 op1=4 crn=8 crm=7 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae2: u64 = 25657
// op0=1 op1=6 crn=8 crm=7 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae3: u64 = 29753
// op0=1 op1=0 crn=8 crm=7 op2=2 reg=REQUIRED
const arm64_sys_tlbi_aside1: u64 = 17466
// op0=1 op1=0 crn=8 crm=7 op2=3 reg=REQUIRED
const arm64_sys_tlbi_vaae1: u64 = 17467
// op0=1 op1=4 crn=8 crm=7 op2=4 reg=NONE
const arm64_sys_tlbi_alle1: u64 = 25660
// op0=1 op1=0 crn=8 crm=7 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale1: u64 = 17469
// op0=1 op1=4 crn=8 crm=7 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale2: u64 = 25661
// op0=1 op1=6 crn=8 crm=7 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale3: u64 = 29757
// op0=1 op1=4 crn=8 crm=7 op2=6 reg=NONE
const arm64_sys_tlbi_vmalls12e1: u64 = 25662
// op0=1 op1=0 crn=8 crm=7 op2=7 reg=REQUIRED
const arm64_sys_tlbi_vaale1: u64 = 17471
// op0=1 op1=0 crn=8 crm=1 op2=0 reg=OPTIONAL
const arm64_sys_tlbi_vmalle1os: u64 = 17416
// op0=1 op1=0 crn=8 crm=1 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae1os: u64 = 17417
// op0=1 op1=0 crn=8 crm=1 op2=2 reg=REQUIRED
const arm64_sys_tlbi_aside1os: u64 = 17418
// op0=1 op1=0 crn=8 crm=1 op2=3 reg=REQUIRED
const arm64_sys_tlbi_vaae1os: u64 = 17419
// op0=1 op1=0 crn=8 crm=1 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale1os: u64 = 17421
// op0=1 op1=0 crn=8 crm=1 op2=7 reg=REQUIRED
const arm64_sys_tlbi_vaale1os: u64 = 17423
// op0=1 op1=4 crn=8 crm=4 op2=0 reg=REQUIRED
const arm64_sys_tlbi_ipas2e1os: u64 = 25632
// op0=1 op1=4 crn=8 crm=4 op2=4 reg=REQUIRED
const arm64_sys_tlbi_ipas2le1os: u64 = 25636
// op0=1 op1=4 crn=8 crm=1 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae2os: u64 = 25609
// op0=1 op1=4 crn=8 crm=1 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale2os: u64 = 25613
// op0=1 op1=4 crn=8 crm=1 op2=6 reg=OPTIONAL
const arm64_sys_tlbi_vmalls12e1os: u64 = 25614
// op0=1 op1=6 crn=8 crm=1 op2=1 reg=REQUIRED
const arm64_sys_tlbi_vae3os: u64 = 29705
// op0=1 op1=6 crn=8 crm=1 op2=5 reg=REQUIRED
const arm64_sys_tlbi_vale3os: u64 = 29709
// op0=1 op1=4 crn=8 crm=1 op2=0 reg=OPTIONAL
const arm64_sys_tlbi_alle2os: u64 = 25608
// op0=1 op1=4 crn=8 crm=1 op2=4 reg=OPTIONAL
const arm64_sys_tlbi_alle1os: u64 = 25612
// op0=1 op1=6 crn=8 crm=1 op2=0 reg=OPTIONAL
const arm64_sys_tlbi_alle3os: u64 = 29704
// op0=1 op1=0 crn=8 crm=6 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae1: u64 = 17457
// op0=1 op1=0 crn=8 crm=6 op2=3 reg=REQUIRED
const arm64_sys_tlbi_rvaae1: u64 = 17459
// op0=1 op1=0 crn=8 crm=6 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale1: u64 = 17461
// op0=1 op1=0 crn=8 crm=6 op2=7 reg=REQUIRED
const arm64_sys_tlbi_rvaale1: u64 = 17463
// op0=1 op1=0 crn=8 crm=2 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae1is: u64 = 17425
// op0=1 op1=0 crn=8 crm=2 op2=3 reg=REQUIRED
const arm64_sys_tlbi_rvaae1is: u64 = 17427
// op0=1 op1=0 crn=8 crm=2 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale1is: u64 = 17429
// op0=1 op1=0 crn=8 crm=2 op2=7 reg=REQUIRED
const arm64_sys_tlbi_rvaale1is: u64 = 17431
// op0=1 op1=0 crn=8 crm=5 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae1os: u64 = 17449
// op0=1 op1=0 crn=8 crm=5 op2=3 reg=REQUIRED
const arm64_sys_tlbi_rvaae1os: u64 = 17451
// op0=1 op1=0 crn=8 crm=5 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale1os: u64 = 17453
// op0=1 op1=0 crn=8 crm=5 op2=7 reg=REQUIRED
const arm64_sys_tlbi_rvaale1os: u64 = 17455
// op0=1 op1=4 crn=8 crm=0 op2=2 reg=REQUIRED
const arm64_sys_tlbi_ripas2e1is: u64 = 25602
// op0=1 op1=4 crn=8 crm=0 op2=6 reg=REQUIRED
const arm64_sys_tlbi_ripas2le1is: u64 = 25606
// op0=1 op1=4 crn=8 crm=4 op2=2 reg=REQUIRED
const arm64_sys_tlbi_ripas2e1: u64 = 25634
// op0=1 op1=4 crn=8 crm=4 op2=6 reg=REQUIRED
const arm64_sys_tlbi_ripas2le1: u64 = 25638
// op0=1 op1=4 crn=8 crm=4 op2=3 reg=REQUIRED
const arm64_sys_tlbi_ripas2e1os: u64 = 25635
// op0=1 op1=4 crn=8 crm=4 op2=7 reg=REQUIRED
const arm64_sys_tlbi_ripas2le1os: u64 = 25639
// op0=1 op1=4 crn=8 crm=6 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae2: u64 = 25649
// op0=1 op1=4 crn=8 crm=6 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale2: u64 = 25653
// op0=1 op1=4 crn=8 crm=2 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae2is: u64 = 25617
// op0=1 op1=4 crn=8 crm=2 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale2is: u64 = 25621
// op0=1 op1=4 crn=8 crm=5 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae2os: u64 = 25641
// op0=1 op1=4 crn=8 crm=5 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale2os: u64 = 25645
// op0=1 op1=6 crn=8 crm=6 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae3: u64 = 29745
// op0=1 op1=6 crn=8 crm=6 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale3: u64 = 29749
// op0=1 op1=6 crn=8 crm=2 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae3is: u64 = 29713
// op0=1 op1=6 crn=8 crm=2 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale3is: u64 = 29717
// op0=1 op1=6 crn=8 crm=5 op2=1 reg=REQUIRED
const arm64_sys_tlbi_rvae3os: u64 = 29737
// op0=1 op1=6 crn=8 crm=5 op2=5 reg=REQUIRED
const arm64_sys_tlbi_rvale3os: u64 = 29741
// op0=1 op1=6 crn=8 crm=4 op2=3 reg=REQUIRED
const arm64_sys_tlbi_rpaos: u64 = 29731
// op0=1 op1=6 crn=8 crm=4 op2=7 reg=REQUIRED
const arm64_sys_tlbi_rpalos: u64 = 29735
// op0=1 op1=6 crn=8 crm=1 op2=4 reg=NONE
const arm64_sys_tlbi_paallos: u64 = 29708
// op0=1 op1=6 crn=8 crm=7 op2=4 reg=NONE
const arm64_sys_tlbi_paall: u64 = 29756
// op0=1 op1=4 crn=8 crm=6 op2=2 reg=NONE
const arm64_sys_tlbi_vmallws2e1: u64 = 25650
// op0=1 op1=4 crn=8 crm=2 op2=2 reg=OPTIONAL
const arm64_sys_tlbi_vmallws2e1is: u64 = 25618
// op0=1 op1=4 crn=8 crm=5 op2=2 reg=OPTIONAL
const arm64_sys_tlbi_vmallws2e1os: u64 = 25642
// op0=1 op1=0 crn=7 crm=15 op2=1
const arm64_sys_dc_civaps: u64 = 17401
// op0=1 op1=0 crn=7 crm=15 op2=5
const arm64_sys_dc_cigdvaps: u64 = 17405
// op0=1 op1=0 crn=12 crm=1 op2=3
const arm64_sys_ic_cdaff: u64 = 17931
// op0=1 op1=0 crn=12 crm=2 op2=0
const arm64_sys_ic_cddi: u64 = 17936
// op0=1 op1=0 crn=12 crm=1 op2=0
const arm64_sys_ic_cddis: u64 = 17928
// op0=1 op1=0 crn=12 crm=1 op2=1
const arm64_sys_ic_cden: u64 = 17929
// op0=1 op1=0 crn=12 crm=1 op2=7
const arm64_sys_ic_cdeoi: u64 = 17935
// op0=1 op1=0 crn=12 crm=2 op2=1
const arm64_sys_ic_cdhm: u64 = 17937
// op0=1 op1=0 crn=12 crm=1 op2=4
const arm64_sys_ic_cdpend: u64 = 17932
// op0=1 op1=0 crn=12 crm=1 op2=2
const arm64_sys_ic_cdpri: u64 = 17930
// op0=1 op1=0 crn=12 crm=1 op2=5
const arm64_sys_ic_cdrcfg: u64 = 17933
// op0=1 op1=4 crn=12 crm=1 op2=3
const arm64_sys_ic_vdaff: u64 = 26123
// op0=1 op1=4 crn=12 crm=2 op2=0
const arm64_sys_ic_vddi: u64 = 26128
// op0=1 op1=4 crn=12 crm=1 op2=0
const arm64_sys_ic_vddis: u64 = 26120
// op0=1 op1=4 crn=12 crm=1 op2=1
const arm64_sys_ic_vden: u64 = 26121
// op0=1 op1=4 crn=12 crm=2 op2=1
const arm64_sys_ic_vdhm: u64 = 26129
// op0=1 op1=4 crn=12 crm=1 op2=4
const arm64_sys_ic_vdpend: u64 = 26124
// op0=1 op1=4 crn=12 crm=1 op2=2
const arm64_sys_ic_vdpri: u64 = 26122
// op0=1 op1=4 crn=12 crm=1 op2=5
const arm64_sys_ic_vdrcfg: u64 = 26125
// op0=1 op1=6 crn=12 crm=1 op2=3
const arm64_sys_ic_ldaff: u64 = 30219
// op0=1 op1=6 crn=12 crm=2 op2=0
const arm64_sys_ic_lddi: u64 = 30224
// op0=1 op1=6 crn=12 crm=1 op2=0
const arm64_sys_ic_lddis: u64 = 30216
// op0=1 op1=6 crn=12 crm=1 op2=1
const arm64_sys_ic_lden: u64 = 30217
// op0=1 op1=6 crn=12 crm=2 op2=1
const arm64_sys_ic_ldhm: u64 = 30225
// op0=1 op1=6 crn=12 crm=1 op2=4
const arm64_sys_ic_ldpend: u64 = 30220
// op0=1 op1=6 crn=12 crm=1 op2=2
const arm64_sys_ic_ldpri: u64 = 30218
// op0=1 op1=6 crn=12 crm=1 op2=5
const arm64_sys_ic_ldrcfg: u64 = 30221
