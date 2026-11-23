const STATUTORY_2027 = {
  b1Single: 12564,
  b2Single: 18000,
  b3Single: 70600,
  b4Single: 285000,
  solzFreigrenzeSingle: 19450,
  anPauschbetrag: 1430,
  bbgRvYear: 106200,
  bbgRvMonth: 8850,
  bbgKvYear: 76500,
  bbgKvMonth: 6375,
  bavMaxTotal: 50976,
  ruerupMaxSingle: 32308,
  iabMaxPurchase: 400000,
  gkvMindestBemessung: 1376.67
};

function calcSingleTariff2027(zve) {
  const x = Math.floor(Math.max(0, zve));
  if (x <= STATUTORY_2027.b1Single) return 0;
  if (x <= STATUTORY_2027.b2Single) {
    const y = (x - STATUTORY_2027.b1Single) / 10000;
    return Math.floor((919.8 * y + 1400) * y);
  }
  if (x <= STATUTORY_2027.b3Single) {
    const z = (x - STATUTORY_2027.b2Single) / 10000;
    const taxAtB2 = Math.floor((919.8 * 0.5436 + 1400) * 0.5436);
    return Math.floor((171.1 * z + 2400) * z + taxAtB2);
  }
  if (x <= STATUTORY_2027.b4Single) {
    return Math.floor(0.42 * x - 11135.63);
  }
  return Math.floor(0.45 * x - 19685.63);
}

function calcTariff2027(zve, isSplitting) {
  return isSplitting ? 2 * calcSingleTariff2027(zve / 2) : calcSingleTariff2027(zve);
}

function calcSolz2027(est, isSplitting) {
  const fg = isSplitting ? STATUTORY_2027.solzFreigrenzeSingle * 2 : STATUTORY_2027.solzFreigrenzeSingle;
  if (est <= fg) return 0;
  return Math.min((est - fg) * 0.119, est * 0.055);
}

function calcFuenftel2027(rawBaseZve, taxableAbfindung, isSplitting, churchRate) {
  const clampedBase = Math.max(0, rawBaseZve);
  const baseEst = calcTariff2027(clampedBase, isSplitting);
  const baseSolz = calcSolz2027(baseEst, isSplitting);
  const baseChurch = baseEst * churchRate;

  const combinedFifth = Math.max(0, rawBaseZve + taxableAbfindung / 5);
  const fifthEst = calcTariff2027(combinedFifth, isSplitting);
  const abfEst = Math.max(0, 5 * (fifthEst - baseEst));

  const totalEst = baseEst + abfEst;
  const totalSolz = calcSolz2027(totalEst, isSplitting);
  const abfSolz = Math.max(0, totalSolz - baseSolz);
  const abfChurch = abfEst * churchRate;

  return {
    baseTax: baseEst + baseSolz + baseChurch,
    abfTax: abfEst + abfSolz + abfChurch
  };
}

function calcEmployeeSocial2027(grossSalary, zbPct, isPkv) {
  const rv = Math.min(grossSalary, STATUTORY_2027.bbgRvYear) * 0.106;
  if (isPkv) return rv;
  const kvRate = 0.073 + (zbPct / 100) / 2 + 0.024;
  return rv + Math.min(grossSalary, STATUTORY_2027.bbgKvYear) * kvRate;
}

function calcMonthlyAlg1Net(monthlyGross, alg1SatzPct) {
  return Math.min(monthlyGross, STATUTORY_2027.bbgRvMonth) * 0.80 * (alg1SatzPct / 100);
}

function findMaxPartnerGrossForSplitting(userRawBaseZve, taxableAbf, churchRate) {
  let low = 0, high = 300000;
  const singleUser = calcFuenftel2027(userRawBaseZve, taxableAbf, false, churchRate);
  for (let i = 0; i < 28; i++) {
    const mid = (low + high) / 2;
    const partnerZve = Math.max(0, mid - STATUTORY_2027.anPauschbetrag - calcEmployeeSocial2027(mid, 2.5, false));
    const singlePartnerEst = calcTariff2027(partnerZve, false);
    const singlePartnerTax = singlePartnerEst + calcSolz2027(singlePartnerEst, false) + singlePartnerEst * churchRate;
    const joint = calcFuenftel2027(userRawBaseZve + partnerZve, taxableAbf, true, churchRate);
    if (joint.baseTax + joint.abfTax <= singleUser.baseTax + singleUser.abfTax + singlePartnerTax) low = mid;
    else high = mid;
  }
  return Math.round(low);
}

function solveAllocation(mode, customOrder, context) {
  let bav = 0, drv = 0, ruerup = 0, pvPurchase = 0;
  let remBaseZve = Math.max(0, context.unoptimizedBaseZve);
  let remAbf = Math.max(0, context.effectiveAbf);
  let remRuerupCap = Math.max(0, context.ruerupCap);

  const order = mode === "liquidity"
    ? ["iab"]
    : mode === "retirement"
      ? ["bav", "drv", "ruerup"]
      : mode === "custom" && Array.isArray(customOrder)
        ? customOrder
        : ["bav", "drv", "ruerup", "iab"];

  for (const lever of order) {
    if (lever === "bav") {
      bav = Math.min(STATUTORY_2027.bavMaxTotal, remAbf);
      remAbf -= bav;
    } else if (lever === "drv") {
      drv = Math.min(60000, remAbf);
      remAbf -= drv * 0.5;
    } else if (lever === "ruerup") {
      ruerup = Math.min(remRuerupCap, remBaseZve);
      remBaseZve -= ruerup;
      remRuerupCap -= ruerup;
    } else if (lever === "iab") {
      const neededDeduction = Math.min(STATUTORY_2027.iabMaxPurchase * 0.5, remBaseZve);
      pvPurchase = Math.round((neededDeduction * 2) / 2500) * 2500;
      remBaseZve -= pvPurchase * 0.5;
    }
  }
  return { bav, drv, ruerup, pvPurchase };
}

function runSimulation(input) {
  const altesMonatsgehalt = Number(input.altesMonatsgehalt || 0);
  const fristMonate = Number(input.fristMonate || 0);
  const bruttoAbfindung = Number(input.bruttoAbfindung || 0);
  const agFiktivGehalt = Number(input.agFiktivGehalt || 0);
  const neuesGehalt2027 = Number(input.neuesGehalt2027 || 0);
  const zbPct = Number(input.kvZusatzbeitragPct || 2.5);
  const isPkv = String(input.preExitGkv || "").includes("PKV");
  const isPflicht = String(input.preExitGkv || "").includes("Pflicht");
  const isSplitting = Boolean(input.isSplitting);
  const partnerGehalt = isSplitting ? Number(input.partnerGehalt2027 || 0) : 0;
  const churchRate = Number(input.churchRate || 0);

  const turboEnabled = Boolean(input.turboEnabled);
  const turboFaktor = Number(input.turboFaktor || 1.5);
  const alg1SatzPct = Number(input.alg1SatzPct || 60);
  const includeAlg1Loss = Boolean(input.includeAlg1Loss);

  const effectiveAbf = turboEnabled
    ? bruttoAbfindung + fristMonate * altesMonatsgehalt * turboFaktor
    : bruttoAbfindung;
  const ruhenszeitMonths = turboEnabled
    ? Math.min(12, fristMonate, Math.ceil((0.45 * effectiveAbf) / Math.max(1, altesMonatsgehalt)))
    : 0;

  const gkvMonthlyRate = isPkv ? 0 : STATUTORY_2027.bbgKvMonth * (0.146 + zbPct / 100 + 0.036);
  const chargeableGkvMonths = turboEnabled ? Math.max(0, ruhenszeitMonths - (isPflicht ? 1 : 0)) : 0;
  const voluntaryGkvTotal = chargeableGkvMonths * gkvMonthlyRate;

  const salaryNoTurbo = altesMonatsgehalt * fristMonate + neuesGehalt2027;
  const salaryTurbo = neuesGehalt2027;
  const actualSalary = turboEnabled ? salaryTurbo : salaryNoTurbo;

  const rvTotal = Math.min(actualSalary, STATUTORY_2027.bbgRvYear) * 0.186;
  const ruerupCap = Math.max(0, (isSplitting ? STATUTORY_2027.ruerupMaxSingle * 2 : STATUTORY_2027.ruerupMaxSingle) - rvTotal);

  const userSocial = calcEmployeeSocial2027(actualSalary, zbPct, isPkv);
  const partnerSocial = calcEmployeeSocial2027(partnerGehalt, zbPct, false);
  const partnerZve = isSplitting
    ? Math.max(0, partnerGehalt - Math.min(partnerGehalt, STATUTORY_2027.anPauschbetrag) - partnerSocial)
    : 0;

  const unoptimizedBaseZve = actualSalary + partnerZve - Math.min(actualSalary, STATUTORY_2027.anPauschbetrag) - userSocial - voluntaryGkvTotal;

  let bav = Math.min(Number(input.bavAmount || 0), STATUTORY_2027.bavMaxTotal);
  let drvV0210 = Number(input.drvV0210Amount || 0);
  let ruerup = Number(input.ruerupAmount || 0);
  let pvPurchase = Math.min(Number(input.pvIabPurchase || 0), STATUTORY_2027.iabMaxPurchase);

  if (input.solverMode && input.solverMode !== "manual") {
    const solved = solveAllocation(input.solverMode, input.customSolverOrder, {
      unoptimizedBaseZve,
      effectiveAbf,
      ruerupCap
    });
    bav = solved.bav;
    drvV0210 = solved.drv;
    ruerup = solved.ruerup;
    pvPurchase = solved.pvPurchase;
  }

  const pvIabDeduction = pvPurchase * 0.5;
  const allowedRuerup = Math.min(ruerup, ruerupCap);

  const taxableAbf = Math.max(0, effectiveAbf - bav - drvV0210 * 0.5);
  const cashBeforeTaxAbf = Math.max(0, effectiveAbf - bav - drvV0210);

  const agSocial = calcEmployeeSocial2027(agFiktivGehalt, zbPct, isPkv);
  const agZve = Math.max(0, agFiktivGehalt - Math.min(agFiktivGehalt, STATUTORY_2027.anPauschbetrag) - agSocial);
  const upfrontBaseEst = calcTariff2027(agZve, isSplitting);
  const upfrontTotEst = calcTariff2027(agZve + taxableAbf, isSplitting);
  const upfrontAbfTax = (upfrontTotEst - upfrontBaseEst) * (1 + churchRate) +
    Math.max(0, calcSolz2027(upfrontTotEst, isSplitting) - calcSolz2027(upfrontBaseEst, isSplitting));
  const sofortNetto2027 = Math.max(0, cashBeforeTaxAbf - upfrontAbfTax);

  const rawBaseZve = unoptimizedBaseZve - allowedRuerup - pvIabDeduction;
  const final2028 = calcFuenftel2027(rawBaseZve, taxableAbf, isSplitting, churchRate);
  const optimalNettoTotal = Math.max(0, cashBeforeTaxAbf - final2028.abfTax);
  const finanzamtRefundOct2028 = optimalNettoTotal - sofortNetto2027;

  const iabSweetSpotDeduction = Math.max(0, rawBaseZve + pvIabDeduction);
  const partnerSplittingBreakEvenMax = findMaxPartnerGrossForSplitting(rawBaseZve - partnerZve, taxableAbf, churchRate);

  const lostNetSalary = Math.max(0, (salaryNoTurbo - salaryTurbo) * 0.58);
  const sprinterNetBonus = turboEnabled ? fristMonate * altesMonatsgehalt * turboFaktor * 0.68 : 0;
  const rvPointsLoss = turboEnabled ? fristMonate * Math.min(altesMonatsgehalt, STATUTORY_2027.bbgRvMonth) * 0.186 : 0;
  const alg1Loss = (turboEnabled && includeAlg1Loss) ? ruhenszeitMonths * calcMonthlyAlg1Net(altesMonatsgehalt, alg1SatzPct) : 0;

  const waterfallSteps = [
    { id: "bonus", label: "+ Sprinter-Prämie", delta: Math.round(sprinterNetBonus), isPositive: true },
    { id: "salary", label: "− Entg. Gehalt", delta: -Math.round(lostNetSalary), isPositive: false },
    { id: "gkv", label: "− Freiw. GKV/PV", delta: -Math.round(voluntaryGkvTotal), isPositive: false },
    { id: "rv", label: "− RV-Punkte", delta: -Math.round(rvPointsLoss), isPositive: false },
    { id: "alg1", label: "− ALG 1 Verlust", delta: -Math.round(alg1Loss), isPositive: false }
  ];

  const expenses = Math.max(500, Number(input.monthlyExpenses || 3500));
  const alg1Monthly = calcMonthlyAlg1Net(altesMonatsgehalt, alg1SatzPct);
  const alg1Months = Number(input.alg1ClaimMonths || 12);
  const postGkv = input.postAlg1GkvMode === "Familienversicherung" ? 0 : STATUTORY_2027.gkvMindestBemessung * (0.146 + zbPct / 100 + 0.036);

  const stdTotalPool = Math.max(0, bruttoAbfindung * 0.72 + fristMonate * (altesMonatsgehalt * 0.58 - expenses));
  const sprTotalPool = Math.max(0, optimalNettoTotal - voluntaryGkvTotal);

  const stdAlg1NetBurn = Math.max(0, expenses - alg1Monthly);
  const stdPostBurn = expenses + postGkv;
  const stdAlg1Covered = Math.min(alg1Months, stdAlg1NetBurn > 0 ? stdTotalPool / stdAlg1NetBurn : alg1Months);
  const stdRemaining = Math.max(0, stdTotalPool - stdAlg1Covered * stdAlg1NetBurn);
  const standardRunwayMonths = fristMonate + stdAlg1Covered + stdRemaining / stdPostBurn;

  const sprAlg1Months = Math.max(0, alg1Months - Math.max(0, ruhenszeitMonths - fristMonate));
  const sprAlg1Covered = Math.min(sprAlg1Months, stdAlg1NetBurn > 0 ? sprTotalPool / stdAlg1NetBurn : sprAlg1Months);
  const sprRemaining = Math.max(0, sprTotalPool - sprAlg1Covered * stdAlg1NetBurn);
  const sprinterRunwayMonths = ruhenszeitMonths + sprAlg1Covered + sprRemaining / stdPostBurn;

  const runwaySegments = [
    { id: "std-1", strategy: "Standard", phaseName: "1. Frist", startMonth: 0, durationMonths: fristMonate },
    { id: "std-2", strategy: "Standard", phaseName: "2. ALG 1", startMonth: fristMonate, durationMonths: Math.round(stdAlg1Covered * 10) / 10 },
    { id: "std-3", strategy: "Standard", phaseName: "3. Privatier", startMonth: fristMonate + stdAlg1Covered, durationMonths: Math.round((stdRemaining / stdPostBurn) * 10) / 10 },
    { id: "spr-1", strategy: "Sprinter", phaseName: "1. Ruhenszeit", startMonth: 0, durationMonths: ruhenszeitMonths },
    { id: "spr-2", strategy: "Sprinter", phaseName: "2. ALG 1", startMonth: ruhenszeitMonths, durationMonths: Math.round(sprAlg1Covered * 10) / 10 },
    { id: "spr-3", strategy: "Sprinter", phaseName: "3. Privatier", startMonth: ruhenszeitMonths + sprAlg1Covered, durationMonths: Math.round((sprRemaining / stdPostBurn) * 10) / 10 }
  ];

  // Section D: Salary-Switch Break-Even Trajectory (15-year cumulative net delta)
  const newJobGrossAnnual = Number(input.newJobGrossAnnual || 65000);
  const growthRate = Number(input.salaryGrowthPct || 2.0) / 100;
  const oldJobGrossAnnual = altesMonatsgehalt * 12;
  const crossoverPoints = [];
  let cumulativeDelta = optimalNettoTotal;
  let breakEvenYear = -1;

  for (let yr = 0; yr <= 15; yr++) {
    crossoverPoints.push({ year: yr, netDelta: Math.round(cumulativeDelta) });
    if (yr > 0) {
      const factor = Math.pow(1 + growthRate, yr);
      const oldNetYear = oldJobGrossAnnual * factor * 0.58;
      const newNetYear = newJobGrossAnnual * factor * 0.62;
      const prevDelta = cumulativeDelta;
      cumulativeDelta += (newNetYear - oldNetYear);
      if (prevDelta >= 0 && cumulativeDelta < 0 && breakEvenYear === -1) {
        breakEvenYear = yr;
      }
    }
  }

  return {
    sofortNetto2027: Math.round(sofortNetto2027),
    finanzamtRefundOct2028: Math.round(finanzamtRefundOct2028),
    optimalNettoTotal: Math.round(optimalNettoTotal),
    ruerupCapRemaining: Math.round(Math.max(0, ruerupCap - allowedRuerup)),
    iabSweetSpotDeduction: Math.round(iabSweetSpotDeduction),
    partnerSplittingBreakEvenMax,
    ruhenszeitMonths,
    waterfallSteps,
    standardRunwayMonths: Math.round(standardRunwayMonths * 10) / 10,
    sprinterRunwayMonths: Math.round(sprinterRunwayMonths * 10) / 10,
    runwaySegments,
    solvedBav: Math.round(bav),
    solvedDrv: Math.round(drvV0210),
    solvedRuerup: Math.round(ruerup),
    solvedPvPurchase: Math.round(pvPurchase),
    crossoverPoints,
    breakEvenYear
  };
}
