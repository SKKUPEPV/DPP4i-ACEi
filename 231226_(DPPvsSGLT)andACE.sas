
options  compress=yes;

%macro t20;
%do year=2012 %to 2022;
%let m=01 02 03 04 05 06 07 08 09 10 11 12;
%do i=1 %to 12;
%let mm=%scan(&m.,&i.);

data sick_1;
set raw.t20_&year.&mm.;
start_dt=mdy(substr(mdcare_strt_dt,5,2), substr(mdcare_strt_dt,7,2),
substr(mdcare_strt_dt,1,4));
format start_dt yymmdd10.;
keep indi_dscm_no cmn_key start_dt form_cd mcare_subj_cd hsptz_path_type
oprtn_yn vshsp_dd_cnt sick_sym1 ;
rename  sick_sym1=sick_cd;
run;

data t20_&mm.;
set sick_1;
run;
%end;

data stt.mainsick_&year.;
set t20_01 - t20_12;
run;

data stt.mainsick_&year.;
set stt.mainsick_&year.;
if FORM_CD in ("02", "07", "10") then inpat=1; else inpat=0;
run;
%end;
%mend;
%t20;

*RX for base drug ACEi;
%macro rx_exp;
%do y=2010 %to 2020;
proc sql;
create table temp_&y. as
select distinct a.*, b.nm_rx as var, b.ingr as cate
from stt.drug_&y. as a
inner join a.cd_drug1 as b on substr(a.drug_cd,1,9)=substr(b.cd_rx,1,9)
where b.nm_rx in ("base");
quit;
%end;
%mend;
%rx_exp;
data temp_2;
set temp_2010 - temp_2020;
rename indi_dscm_no=jid cmn_key=mid;
run;
data a.tot_rx_base; set temp_2; run;
data base;
set a.tot_rx_base;
format end_dt yymmdd10.;
end_dt=stt_dt+tot_day-1;
if stt_dt>= mdy(01,01,2011);
keep jid stt_dt end_dt var;
run;
/*New user of ACEi between 2011 and 2020*/
data tot_rx_exp2014;
set a.tot_rx_base;
if mdy(1,1,2010)<=stt_dt<=mdy(12,31,2020);
run;
proc sql;
create table a.cht_base as 
select distinct jid, min(stt_dt) as exp_1st_dt format yymmdd10.
from tot_rx_exp2014
group by 1
order by 1; 
quit;
proc sql;select count (distinct jid) from a.cht_base; quit;/*503,249*/
data co1;
set a.cht_base;
if exp_1st_dt>=mdy(1,1,2011);
run;/*238,607*/
proc sql;
create table a.co1 as
select distinct a.* ,b.*
from co1 a inner join base b
on a.jid=b.jid
order by jid, stt_dt;
quit;
data as2;
set a.co1;
by jid stt_dt;
format lag_end_dt yymmdd10.;
lag_end_dt=lag(end_dt)+180;
if first.jid then do; lag_end_dt=.; flag_1st=1; end;
else if stt_dt<=lag_end_dt then flag_1st=0;
else flag_1st=1;
retain episode 0;
episode=episode+flag_1st;
run;
proc sql;
create table as3 as
select distinct jid, exp_1st_dt, stt_dt, episode, max(end_dt)+180 as disc_dt format yymmdd10.
from as2
group by jid, episode;
quit;
proc sql;
create table disc as
select distinct *
from as3
group by jid
having min(episode)=episode;
quit;
proc sql;
create table a.co2 as
select distinct a.*, b.disc_dt
from co1 a left join disc b
on a.jid=b.jid;
quit;/*238,607*/
*RX for exposure(SGLT2 and DPP4);
%macro rx_exp;
%do y=2010 %to 2022;
proc sql;
create table temp_&y. as
select distinct a.*, b.nm_rx as var, b.ingr as cate
from stt.drug_&y. as a
inner join e.cd_drug1 as b on substr(a.drug_cd,1,9)=substr(b.cd_rx,1,9)
where b.nm_rx in ("exp1", "comp1");
quit;
%end;
%mend;
%rx_exp;

data temp_2;
set temp_2010 - temp_2022;
rename indi_dscm_no=jid cmn_key=mid;
run;
data e.tot_rx_exp; set temp_2; run;
data a.tot_rx_exp; set e.tot_rx_exp; run;

data exp;
set a.tot_rx_exp;
format end_dt yymmdd10.;
end_dt=stt_dt+tot_day-1;
if mdy(9,1,2014)<=stt_dt<=mdy(12,31,2020);
keep jid stt_dt end_dt var;
run;
/*병용한 환자 뽑기, 두가지 가능성 존재, ppt*/
/*240108, cohort1*/
proc sql;
create table a.co3 as
select distinct a.jid, b.stt_dt, b.end_dt
from a.co2 a inner join exp b
on a.jid=b.jid and (a.exp_1st_dt<=b.stt_dt<=a.disc_dt );
quit;
proc sql;
create table a.co3_2 as
select distinct a.jid, a.exp_1st_dt, b.end_dt
from a.co2 a inner join exp b
on a.jid=b.jid and (b.stt_dt<a.exp_1st_dt and b.end_dt>=a.exp_1st_dt );
quit;
proc sql; select count (distinct jid) from a.co3; quit; /*110,598*/
proc sql; select count (distinct jid) from a.co3_2; quit; /*32,335*/
proc sql;
create table a.cht1 as 
select distinct jid, min(stt_dt) as exp_1st_dt format yymmdd10.
from a.co3
group by 1
order by 1; 
quit;
\
data temp_1;
set d.info_2010 - d.info_2020;
run;
proc sql;
create table a.incl1_1 as
select distinct a.*,b.sex,b.age,b.soeco
from a.cht1 as a left join temp_1 as b
on a.jid=b.indi_dscm_no and year(a.exp_1st_dt)=std_yr;
quit;
data excl1;
set a.incl1_1;
if sex='' or age<18;
rename indi_dscm_no=jid;
run;
proc sql;
create table a.incl1 as 
select distinct *
from a.cht1  
where jid not in (select jid from excl1);
quit;
proc sql;select count (distinct jid) from a.incl1; quit;/*110,559*/


/*ESRD/dialysis*/
proc sql;
create table excl2_1 as
select distinct a.*
from a.incl1 as a inner join e.sick as b
on a.jid=b.jid and 0<=a.exp_1st_dt-b.start_dt<=365
where substr(b.sick_cd,1,3) in ("Z49") or substr(b.sick_cd,1,4) in ("N185", "Z992") ; 
quit;
data proc;
set stt.proc_2010 - stt.proc_2020;
if substr(proc_cd,1,5) in ("O7020", "O7061", "O7062");
run;
proc sql;
create table excl2_2 as
select distinct a.*,b.indi_dscm_no as jid
from a.incl1 as a inner join proc as b
on a.jid=b.indi_dscm_no and 0<=a.exp_1st_dt-b.stt_dt<=365;
quit;
data excl2;
set excl2_1 excl2_2;
run;
proc sql;
create table a.excl2 as
select distinct *
from excl2;
quit;
proc sql;
create table a.incl2 as
select distinct *
from a.incl1
where jid not in (select jid from a.excl2);
quit;/**/
proc sql;select count (distinct jid) from a.incl2; quit;/*106,458*/

/*1227*/
/*both prescription on same date*/
proc sql;
create table excl3_1 as 
select distinct a.jid, a.exp_1st_dt, b.stt_dt, b.var
from a.incl2 a inner join a.tot_rx_exp b
on a.jid=b.jid and a.exp_1st_dt=b.stt_dt;
quit;/*여기에서 comp1은 dpp4!*/ 
proc sql;
create table excl3_2 as 
select distinct *, count(var) as cnt
from excl3_1
group by jid;
quit;
data excl3_3;
set excl3_2;
if cnt>1;
run;
proc sql;
create table a.incl3_1 as
select distinct jid, exp_1st_dt
from a.incl2
where jid not in (select jid from excl3_3);
quit;
proc sql;
create table a.incl3 as
select distinct a.jid, a.exp_1st_dt, b.var
from a.incl3_1 a inner join a.tot_rx_exp b
on a.jid=b.jid and a.exp_1st_dt=b.stt_dt;
quit;
proc freq data=a.incl3;table var;quit;/*9,887; 95,800*/


/*prior 1 year use of DPP4 AND SGLT2*/
proc sql;
create table a.excl4 as
select distinct a.*
from a.incl3 as a inner join a.tot_rx_exp as b
on a.jid=b.jid and 0<a.exp_1st_dt-b.stt_dt<=365;
quit;
proc sql;
create table a.incl4 as
select distinct *
from a.incl3
where jid not in (select jid from a.excl4);
quit;/**/
proc freq data= a.excl4;table var;run;/**/
proc freq data= a.incl4;table var;run;/*6,704; 42,116*/

/*stt.mainsick_ 는 주상병코드만 포함; 암outcome정의 때 필요*/
/*allcancer-free cohorts, ever before lookback window applied*/
proc sql;
create table excl5 as 
select distinct a.*
from a.incl4 as a left join e.sick as b
on a.jid=b.jid and 0<=a.exp_1st_dt-b.start_dt
where substr(b.sick_cd,1,1) in ("C");
quit; 
proc sql;
create table a.incl5 as
select distinct *
from a.incl4
where jid not in (select jid from excl5);
quit;
proc sql;select count (distinct jid) from a.incl5; quit;/*43,802*/
proc freq data=a.incl5;table var;quit;/*6207;37595*/


/*follow-up (outcome, dth, sted)*/
/*outcome: combined presence of dementia diagnosis and prescription*/
data e.mainsick;
set stt.mainsick_2010-stt.mainsick_2022;
keep indi_dscm_no sick_cd inpat start_dt;
rename indi_dscm_no=jid;
run;
proc sql;
create table a.lc_dx as 
select distinct *
from e.mainsick 
where substr(sick_cd,1,3) in ("C33","C34") and jid in (select jid from a.incl5);
quit; /**/
/*Outpatients 3 times within 1 year, inpatient1*/
data lc1;
set a.lc_dx;
if inpat=1;
run;
data lc2;
set a.lc_dx;
if inpat=0;
drop sick_cd;
run;
proc sort data=lc2; by jid start_dt;quit;
proc sql;
create table lc3 as 
select distinct *, count(*) as cnt
from lc2
group by jid;
quit;
data lc4;
set lc3;
if cnt>=3;
run;
proc sql;
create table lc5 as
select distinct jid, start_dt, cnt, min(start_dt) as indt format yymmdd10.
from lc4
group by jid;
quit;
data lc6;
set lc5;
day=start_dt-indt;
if day<=365;
run;
proc sql;
create table lc7 as 
select distinct *, count(*) as CNT1Y
from lc6
group by jid;
quit;
data lc8;
set lc7;
if cnt1Y>=3;
run;
data a.out_lc_glp;
set lc1 lc8;
keep jid start_dt;
run;
proc sort data=a.out_lc_glp; by jid start_dt;quit;

proc sql;
create table out1 as
select distinct a.*,b.start_dt as LC_DT format yymmdd10.
from a.incl5 as a inner join a.out_lc_glp as b
on a.jid=b.jid and a.exp_1st_dt<b.start_dt;
quit;/**/
proc sql;
create table out2 as 
select distinct jid,exp_1st_dt,min(LC_DT) as LC_DT format yymmdd10.
from out1
group by 1;
quit;/**/

/*final followup cohort*/
proc sql;
create table a.lung_fu as
select distinct  a.*, c.*, mdy(12,31,2022) as sted format yymmdd10., e.dth_dt
from a.incl5 as a
left join out2 as c on a.jid=c.jid
left join stt.tot_death as e on a.jid=e.indi_dscm_no and e.dth_dt>a.exp_1st_dt;
quit;
proc sql;select count (distinct jid) from a.lung_fu;quit;/*43,802*/

/*fu<=365 then delete, switching 안고려*/
data a.lung_fu1;
set a.lung_fu;
if (min(LC_DT, dth_dt, sted) - exp_1st_dt) <=365 then delete;
run;
data a.lung_fu2;
set a.lung_fu1;
if var="comp1" then exposure=0;else exposure=1;
drop cate;
run;/*sglt2 1 dpp4 0*/
proc freq data=a.lung_fu2;table var;quit;/*6,118; 35,990; total 42,108 */
/*crude hr, ITT*/
data temp1;
set a.lung_fu2;
fu1=min(LC_DT, dth_dt, sted) - (exp_1st_dt+365);
if LC_DT^="." and LC_DT =min(LC_DT, dth_dt, sted) then outcome1=1; else outcome1=0;
run;
proc phreg data=temp1;
	class outcome1 exposure(ref='1');
	model fu1*outcome1(0)=exposure /rl;
quit;


/*interested rx*/
%macro int_cd;
%do y=2013 %to 2020;
proc sql;
create table int_drug_&y. as
select *
from stt.drug_&y.
where indi_dscm_no in (select jid from a.lung_fu2);
quit;


%end;
%mend;
%int_cd;
data a.int_drug;
set int_drug_2013-int_drug_2020;
run;
proc sql;select count (distinct indi_dscm_no) from a.int_drug; quit;/*42,108*/

proc sql;
create table a.int_sick as 
select distinct * 
from e.sick
where jid in (select jid from a.lung_fu2);
quit;
proc sql;select count (distinct jid) from a.int_sick; quit;/*42,108*/
data e.proc;
set stt.proc_2013 - stt.proc_2020;
run;
proc sql;
create table a.int_proc as 
select distinct * 
from e.proc
where indi_dscm_no in (select jid from a.lung_fu2);
quit;
proc sql;select count (distinct indi_dscm_no) from a.int_proc; quit;/*42,107*/

/*Baseline characteristics*/
/*age, sex, ses*/
proc sql;
create table a.cohort1 as
select distinct a.*, b.sex, b.age, b.soeco
from a.lung_fu2 a inner join a.incl1_1 b
on a.jid=b.jid;
quit;

/*comorbidities & medicaiton: sick, drug*/
proc sql;
create table a.var_1 as
select distinct a.jid, a.start_dt as stt_dt, a.inpat, b.nm_dx as var, b.dx as cate
from a.int_sick as a
inner join a.cd_sick as b on substr(sick_cd,1,3)=b.cd_dx or substr(sick_cd,1,4)=b.cd_dx
where substr(b.nm_dx,1,5)="comor";
quit;

proc sql;
create table a.var_2 as
select distinct a.indi_dscm_no as jid, a.stt_dt, b.nm_rx as var, b.rx as cate
from a.int_drug as a
inner join a.cd_drug1 as b on a.drug_cd=b.cd_rx
where substr(b.nm_rx,1,5)="comed"  or substr(b.nm_rx,1,6)="DM_med";
quit;
proc sql;
create table a.var_3 as
select distinct a.indi_dscm_no as jid, a.stt_dt, b.nm_proc as var, b.proc as cate
from a.int_proc as a
inner join a.cd_proc as b on substr(a.proc_cd,1,5)=b.cd_proc
where substr(b.nm_proc,1,5)="comor" or substr(b.nm_proc,1,5)="visit";
quit;
data a.var_4;
length var cate $ 30;
set a.var_1 a.var_2 a.var_3;
run;
/*240425*/
proc sql;
create table a.cov_3 as
select distinct a.jid, a.exp_1st_dt, b.*
from a.cohort1 as a
left join a.var_4 as b on a.jid=b.jid and a.exp_1st_dt - 365 <= b.stt_dt < a.exp_1st_dt;
quit;

data a.mark1;
run;

%macro cov1;
proc sql;
create table cov_4 as
select distinct jid, exp_1st_dt
%do a=1 %to 8;
	, (case when var="comor&a." then 1 else 0 end) as comor&a.
%end;
%do c=1 %to 2;
	, (case when var="comed&c." then 1 else 0 end) as comed&c.
%end;
%do f=1 %to 7;
	, (case when var="DM_med&f." then 1 else 0 end) as DM_med&f.
%end;
from a.cov_3;
quit;

proc sql;
create table a.cov_5 as
select distinct jid
%do a=1 %to 8;
	, max(comor&a.) as comor&a.
%end;
%do c=1 %to 2;
	, max(comed&c.) as comed&c.
%end;
%do f=1 %to 7;
	, max(DM_med&f.) as DM_med&f.
%end;
from cov_4
group by jid;
quit;
%mend;
%cov1;
/*no. of diabetic medications being taken, level of antidiabetic treatment*/
data a.cov_6;
set a.cov_5;
n_dm_med=sum(DM_med1,DM_med2,DM_med3,DM_med4,DM_med5,DM_med6,DM_med7);

if 0 <= n_dm_med < 2 then n_dm_med_grp=1;
else if 2 <= n_dm_med < 4 then n_dm_med_grp=2;
else if 4 <= n_dm_med then n_dm_med_grp=3;
if DM_med7=1 then lv_dm_trt=3;
else if n_dm_med >= 2 then lv_dm_trt=2;
else if n_dm_med in (0,1) then lv_dm_trt=1;
run;

/*Chalson Comorbidity Index */
proc import out=a.CCI datafile="CCI.xlsx" dbms=xlsx replace; sheet="Sheet1"; run;
proc sql;
create table cci1 as 
select distinct a.jid, a.exp_1st_dt, max(c.score) as score1
from a.cohort1 as a
left join a.int_sick as b on a.jid=b.jid and a.exp_1st_dt-365<=b.start_dt<exp_1st_dt
left join a.cci as c on substr(b.sick_cd,1,3)=c.code or substr(b.sick_cd,1,4)=c.code
group by a.jid,c.type;
quit;
proc sql;
create table cci2 as 
select distinct jid, exp_1st_dt, sum(score1) as cci
from cci1 
group by jid;
quit;
data cov_7;
set cci2; 
if cci=0 then cci_grp=1;
else if cci=1 then cci_grp=2;
else if cci=2 then cci_grp=3;
else if cci>=3 then cci_grp=4;
else if cci="." then cci_grp=1;
drop cci;
run;

/*No. of hospitalization in the past year*/
proc sql;
create table cov_8 as
select distinct a.jid, a.start_dt as stt_dt, a.inpat
from e.sick as a
inner join a.cohort1 as c on a.jid=c.jid and c.exp_1st_dt-365<=a.start_dt<c.exp_1st_dt;
quit;
proc sql;
create table inp as 
select distinct jid, sum(inpat) as inp
from cov_8
group by jid;
quit;
proc sql;
create table inp1 as 
select distinct a.jid, b.inp as n_inpat
from a.cohort1 a left join inp b
on a.jid=b.jid;
quit;
data a.cov_10;
set inp1;

if n_inpat <= 0 then n_inpat_cat=1;
else if 1 <= n_inpat <= 2 then n_inpat_cat=2;
else if 3 <= n_inpat then n_inpat_cat=3;

run;
proc freq data=a.cov_10;table n_inpat_cat n_inpat;quit;

proc sql;
create table lab as
select *
from stt.healthexam_all_1201
where indi_dscm_no in (select jid from a.cohort1);
quit;
proc sort data=lab; by indi_dscm_no exam_dt; run;
/*lab data*/
proc sql;
create table cohort_smkdrk as
select distinct a.jid, b.drk, b.smk, b.exam_dt
from a.cohort1 as a left join d.smkdrk_fin as b 
on a.jid=b.indi_dscm_no and a.exp_1st_dt-1095 <= b.exam_dt <= a.exp_1st_dt;
quit;
proc sort data=cohort_smkdrk out=cohort_smkdrk1;
by jid exam_dt;
run;
data cohort_smkdrk2;
set cohort_smkdrk1;
by jid;
if last.jid;
run;
data cohort_smkdrk3;
set cohort_smkdrk2;
if smk=. then smk=99;
if drk=. then drk=99;
run;
/*No of outpatients*/
proc sql;
create table a.outp1 as
select distinct a.jid, a.start_dt as stt_dt, a.inpat
from a.int_sick as a
inner join a.cohort1 as c on a.jid=c.jid and c.exp_1st_dt-365<=a.start_dt<c.exp_1st_dt
where a.inpat=0;
quit;
proc sql;
create table outp2 as 
select distinct jid, count(inpat) as outp
from a.outp1
group by jid;
quit;
proc sql;
create table outp3 as 
select distinct a.jid, b.outp as n_outp
from a.cohort1 a left join outp2 b
on a.jid=b.jid;
quit;
proc freq data=outp3;table n_outp;quit;

/*Master file*/
proc sql;
create table master1 as
select distinct a.*, b.*, c.cci_grp, d.n_inpat_cat, f.*, g.n_outp
from a.cohort1 as a 
left join a.cov_6 as b on a.jid=b.jid 
left join cov_7 as c on a.jid=c.jid
left join a.cov_10 as d on a.jid=d.jid
left join cohort_smkdrk3 as f on a.jid=f.jid
left join outp3 as g on a.jid=g.jid
group by a.jid;
quit;

data master2;
set master1;
if year(exp_1st_dt) in (2014) then calen=1;
if year(exp_1st_dt) in (2015) then calen=2;
if year(exp_1st_dt) in (2016) then calen=3;
if year(exp_1st_dt) in (2017) then calen=4;
if year(exp_1st_dt) in (2018) then calen=5;
if year(exp_1st_dt) in (2019) then calen=6;
if year(exp_1st_dt) in (2020) then calen=7;
if 1<=soeco<=3 then income=1;
if 4<=soeco<=7 then income=2;
if 8<=soeco<=10 then income=3;
drop soeco;
run;

data a.master;
set master2;
run;
data a.master1;
set a.master;
if 18<=age<=39 then agegp=1;
else if 40<=age<=64 then agegp=2;
else agegp=3;
run;

/*emergency */
proc sql;
create table temp1 as
select distinct jid, (case when var="visit_ed" then 1 else 0 end) as emer
from a.cov_3;
quit;
proc sql;
create table temp2 as 
select distinct jid, emer, sum(emer) as n_emer
from temp1
group by jid;
quit;
proc sql;
create table temp3 as
select distinct a.*, b.n_emer
from a.master1 a left join temp2 b
on a.jid=b.jid;
quit;
data temp4;
set temp3;
if n_emer=. then n_emer=0;
run; 
proc freq data=temp4;table n_emer;quit;
data a.master2;
set temp4;
run;

/*ACE duration before dual therapy*/
proc sql;
create table test3 as
select distinct a.*, a.exp_1st_dt-b.exp_1st_dt as day, c.n_inpat
from a.master2 as a left join a.co2 as b on a.jid=b.jid
left join a.cov_10 as c on a.jid=c.jid
;
quit; 
proc tabulate data=test3;
var day;
class exposure;
table
(day), (exposure all)  * (mean median q1 q3 min max)
;
run;/**/
data a.master2;
set test3;
if n_outp=. then n_outp=0;
if n_inpat=. then n_inpat=0;
run;
proc freq data=a.master2; table smk; quit;
/*other lab data: stt.healthexam_all_1201*/
proc sql;
create table lab as
select *
from stt.healthexam_all
where indi_dscm_no in (select jid from a.master2/*main cohort*/);
quit;
proc sort data=lab; by indi_dscm_no exam_dt; run;
proc sql;
create table cohort_lab as
select distinct a.*, b.g1e_bmi as bmi, b.g1e_sgot as ast, b.g1e_sgpt as alt, b.g1e_gfr as gfr, b.g1e_fbs as fbs,
b.g1e_ggt as ggt, b.g1e_tot_chol as tc, b.g1e_tg as tg, b.g1e_ldl as ldl, b.g1e_hdl as hdl, b.g1e_wstc as wc, b.drk, b.smk, b.exam_dt
from a.master2 as a left join lab as b 
on a.jid=b.indi_dscm_no and a.exp_1st_dt-1095 <= exam_dt <= a.exp_1st_dt;
quit;
proc sort data=cohort_lab out=cohort_lab1;
by jid exam_dt;
run;
data a.cohort_lab;
set cohort_lab1;
by jid;
if last.jid;
run;

proc sql;
create table a.master3 as 
select distinct a.*, b.bmi
from a.master2 a left join a.cohort_lab b 
on a.jid=b.jid;
quit;
/*table1*/
proc tabulate data=a.master2;
var day age n_outp;
class sex agegp income calen exposure comed1 comed2 comor8 dm_med1-dm_med7 n_dm_med_grp lv_dm_trt cci_grp n_inpat_cat 
n_emer drk smk
 ;
table
(sex agegp income calen exposure comed1 comed2 comor8 dm_med1-dm_med7 n_dm_med_grp lv_dm_trt cci_grp n_inpat_cat 
n_emer drk smk),
(exposure all)  * (N colpctn)
;
run;
proc tabulate data=a.master2;
var day age n_outp;
class exposure;
table
(day age n_outp), (exposure all)  * (mean std median q1 q3 min max)
;
run;

%stddiff( inds = e.master2 , /*dataset명*/
                 groupvar = exposure, /*그룹 구분 기준 변수-숫자형*/
                 numvars = age bmi fbs ast alt gfr ggt tc tg ldl hdl wc, /*숫자형 변수-변수타입도 숫자형으로 되어있어야 함*/
                 charvars = smk drk sex agegp income calen comor1 comor2 comor3 comor4 comor5 comor6 comor7 comor8 comor9 comor10 comor11 comor12 comor13
 comor14 comor15 comor16 comor17 comor18 comor19 comor20 comor21 Mental1 Mental2 Mental3 Mental4 Mental5 Mental6 Mental7 comed1 comed2 comed3 
comed4 comed5 comed6 comed7 comed8 comed9 comed10 comed11
mental_med1 mental_med2 mental_med3 mental_med4 mental_med5 dm_med1 dm_med2 dm_med3 dm_med4 dm_med5 dm_med6 dm_med7 n_dm_med_grp lv_dm_trt cci_grp n_inpat_cat 
n_inpat_ment n_outp_ment n_mental_med_grp n_emer, /*범주형 변수-문자형으로 되어있어야 함*/
                 wtvar = , /*가중치-없어도 됨, 웬만한 경우엔 공란*/
                 stdfmt =8.3, /*나올 결과값 sd를 소숫점 몇자리까지 보여줄 것이냐, 보통 5.3*/
                 outds =  tt   /*output dataset명*/);

/*Ps matching*/
proc logistic data=a.master3 ;
class smk drk sex agegp income calen comor1 comor2 comor3 comor5 comor6 comor7 comor8 comed1 comed2 
dm_med1 dm_med2 dm_med3 dm_med4 dm_med5 dm_med6 dm_med7 n_dm_med_grp lv_dm_trt cci_grp ;
model exposure= day n_inpat n_emer n_outp smk drk sex agegp income calen comor1 comor2 comor3 comor5 comor6 comor7 comor8 comed1 comed2 
dm_med1 dm_med2 dm_med3 dm_med4 dm_med5 dm_med6 dm_med7 n_dm_med_grp lv_dm_trt cci_grp ;
output out=temp prob=prob;
run;/*0.741*/
 %OneToManyMTCH (
 work, /* Library Name */
 temp, /* Data set of all patients */
 exposure, /* Dependent variable that indicates Case or Control */
/* Code 1 for Cases, 0 for Controls */
 , /* Site/Hospital ID */
 jid, /* Patient ID */
 matches, /* Output data set of matched pairs */
 1); /* Number of controls to match to each case */
proc freq data=matches;table exposure;run;/*5965*2*/
proc tabulate data=matches;
var age ;
class sex agegp income calen exposure comor1-comor21 Mental1-Mental7 comed1-comed11 
mental_med1-mental_med5 dm_med1-dm_med7 n_dm_med_grp lv_dm_trt cci_grp n_inpat_cat 
n_inpat_ment n_outp_ment n_mental_med_grp n_emer smk_ava drk_ava
 ;
table
(sex agegp income calen exposure comor1-comor21 Mental1-Mental7 comed1-comed11 
mental_med1-mental_med5 dm_med1-dm_med7 n_dm_med_grp lv_dm_trt cci_grp n_inpat_cat 
n_inpat_ment n_outp_ment n_mental_med_grp n_emer smk_ava drk_ava ),
(exposure all)  * (N colpctn)
;
run;
proc tabulate data=matches;
var age n_outp;
class drk smk exposure
 ;
table
(drk smk ),
(exposure all)  * (N colpctn)
;
run;
proc tabulate data=matches;
var age bmi fbs ast alt gfr ggt tc tg ldl hdl wc;
class exposure;
table
(age bmi fbs ast alt gfr ggt tc tg ldl hdl wc), (exposure all)  * (mean std)
;
run;
%stddiff( inds = matches , /*dataset명*/
                 groupvar = exposure, /*그룹 구분 기준 변수-숫자형*/
                 numvars = age bmi fbs ast alt gfr ggt tc tg ldl hdl wc, /*숫자형 변수-변수타입도 숫자형으로 되어있어야 함*/
                 charvars = smk drk sex agegp income calen comor1 comor2 comor3 comor4 comor5 comor6 comor7 comor8 comor9 comor10 comor11 comor12 comor13
 comor14 comor15 comor16 comor17 comor18 comor19 comor20 comor21 Mental1 Mental2 Mental3 Mental4 Mental5 Mental6 Mental7 comed1 comed2 comed3 
comed4 comed5 comed6 comed7 comed8 comed9 comed10 comed11
mental_med1 mental_med2 mental_med3 mental_med4 mental_med5 dm_med1 dm_med2 dm_med3 dm_med4 dm_med5 dm_med6 dm_med7 n_dm_med_grp lv_dm_trt cci_grp n_inpat_cat 
n_inpat_ment n_outp_ment n_mental_med_grp n_emer, /*범주형 변수-문자형으로 되어있어야 함*/
                 wtvar = , /*가중치-없어도 됨, 웬만한 경우엔 공란*/
                 stdfmt =8.3, /*나올 결과값 sd를 소숫점 몇자리까지 보여줄 것이냐, 보통 5.3*/
                 outds =  tt   /*output dataset명*/);
data temp1;
set matches;
fu1=min(LC_DT, dth_dt, sted) - (exp_1st_dt+365);
if LC_DT^="." and LC_DT =min(LC_DT, dth_dt, sted) then outcome1=1; else outcome1=0;
run;
proc tabulate data=temp1;
var fu1;
class exposure;
table
(fu1), (exposure all)  * (mean median q1 q3 min max)
;
run;
%macro out;
%do i=1 %to 1;
proc phreg data=temp1;
	class outcome&i. exposure(ref='1');
	model fu&i.*outcome&i.(0)=exposure /rl;
quit;

proc sql;
	create table ir1 as
	select distinct  exposure, sum(outcome&i.) as no_of_event
	from temp1
	where outcome&i.=1
	group by 1;
quit;
proc sql;
	create table ir2 as
	select distinct exposure, round(sum(fu&i.)/365.25,1) as total_py
	from temp1
	group by 1;
quit;
proc sql;
	create table ir3_&i. as
	select distinct a.exposure, a.no_of_event, b.total_py,
		round((a.no_of_event/b.total_py)*1000,0.01) as Incidence_rate,
		round(quantile('chisq',0.025,a.no_of_event*2)/((b.total_py/1000)*2),0.01) as lci,
		round(quantile('chisq',0.975,(a.no_of_event+1)*2)/((b.total_py/1000)*2),0.01) as uci
	from ir1 a left join ir2 b on a.exposure=b.exposure
;
quit;
%end;
%mend;
%out;
/*as treated: (ACE DISC, SGLT DISC, DPP DISC, SGLT SWCH, DPP SWCH)+365*/
/*ace discondt는 'a.co2'의 disc_dt임*/
/*sglt2 dpp4의 중단 또는 swch 날짜*/
data exp;
set a.tot_rx_exp;
format end_dt yymmdd10.;
end_dt=stt_dt+tot_day-1;
if stt_dt>= mdy(09,01,2014);
keep jid stt_dt end_dt var;
run;
proc sql;
create table as1 as
select distinct a.*,b.stt_dt, b.end_dt, b.var as type
from a.MASTER3 as a inner join exp as b
on a.jid=b.jid and a.exp_1st_dt<=b.stt_dt;
quit;
data as2;
set as1;
by jid stt_dt;
format lag_end_dt yymmdd10.;
lag_end_dt=lag(end_dt)+90;
if first.jid then do; lag_end_dt=.; flag_1st=1; end;
else if stt_dt<=lag_end_dt then flag_1st=0;
else flag_1st=1;
retain episode 0;
episode=episode+flag_1st;
run;
proc sql;
create table as3 as
select distinct jid, exp_1st_dt, stt_dt, episode, max(end_dt)+90 as disc_dt format yymmdd10.
from as2
group by jid, episode;
quit;
proc sql;
create table disc as
select distinct *
from as3
group by jid
having min(episode)=episode;
quit;
proc sql;
create table switch as 
select distinct a.*, b.stt_dt as switching_dt, b.type
from a.master2 as a inner join as1 as b
on a.jid=b.jid and a.var^=b.type;
quit;
data switch1;
set switch;
keep jid var exp_1st_dt type switching_dt;
run;
proc sql;
create table swch as 
select distinct jid, min(switching_dt) as swch_dt format yymmdd10.
from switch
group by jid;
quit;
proc sql;
create table a.master_lc_as as
select distinct a.*, b.disc_dt as diadisc_dt format yymmdd10., c.swch_dt, d.disc_dt as acedisc_dt format yymmdd10.
from a.master3 as a left join disc as b on a.jid=b.jid 
left join swch as c on a.jid=c.jid
left join a.co2 as d on a.jid=d.jid;
quit;

/*main analysis, smk included, switching considered only*/
data labco1;
set a.master_lc_as;
if 0<bmi<25 then bmigp=1; else if 25<=bmi<30 then bmigp=2; else if 30<=bmi then bmigp=3; else bmigp=99; 
run;

proc tabulate data=labco1;
var age;
class smk bmigp exposure;
table
(smk bmigp exposure),
(exposure all)  * (N colpctn)
;
run;

data temp1;
set labco1;
if exposure=0 then exp=1; else exp=0;
drop exposure;
fu1=min(LC_DT, dth_dt, sted, swch_dt+365) - (exp_1st_dt+365);
if LC_DT^="." and LC_DT =min(LC_DT, dth_dt, sted, swch_dt+365) then outcome1=1; else outcome1=0;
run;
data temp2;
set temp1;
rename exp=exposure;
run;
data fine_out2;
set temp2;
run;
proc univariate data=fine_out2;
var fu1; run;
%fine_stratification (
in_data=fine_out2, 
exposure=exposure, 
PS_provided=no, 
ps_var=ps, 
ps_class_var_list=smk sex agegp income calen comor1 comor2 comor3 comor5 comor6 comor7 lv_dm_trt comed1 comed2 
dm_med1 dm_med2 dm_med3 dm_med4 dm_med5 dm_med6 dm_med7 n_dm_med_grp cci_grp , 
ps_cont_var_list=day n_inpat n_emer n_outp,
interactions=, 
PSS_method=exposure,
n_of_strata=50 , 
out_data=PS_FS, 
id_var=jid, 
estimand=att, 
effect_estimate=hr,
outcome=outcome1, 
survival_time=fu1, 
time_unit=days,
out_excel=/240621_ddiswcindmissmk, 
work_lib=
);
/*km curve*/
data lifetable1;
set PS_FS;
fu_year = fu1 / 365.25;
l_fuyear=log(fu_year/1000);
run;
ods graphics on;
ods output survivalplot=survivalplot;

proc lifetest data=lifetable1
plots=survival(atrisk(outside)=0 to 8 by 1 nocensor)
outs=result(drop=SDF_LCL SDF_UCL) notable;
weight psweight;
time fu_year*outcome1(0);
strata exposure / test=logrank;
run;

data kmoutcome1;
	set result;
	keep exposure fu_year survival;
run;
%MACRO lifetable;
%do i=1 %to 1;

data lifetable&i.;
set PS_FS;
fu_year = fu&i. / 365.25;
l_fuyear=log(fu_year/1000);


proc lifetest data=lifetable&i.
plots=s(atrisk(outside)=0 to 8 by 1 nocensor)
outs=result(drop=SDF_LCL SDF_UCL) notable;
weight psweight;
time fu_year*outcome&i.(0);
strata exposure / test=logrank;
ods output homtests=ranktestoutcome&i.;
run;

data kmoutcome&i.;
	set result;
	keep exposure fu_year survival;
run;

proc export data=kmoutcome&i. outfile="/240621ddikm.xlsx" dbms=xlsx replace;
sheet="kmoutcome&i."; run;

%end;
%MEND;
%lifetable;
