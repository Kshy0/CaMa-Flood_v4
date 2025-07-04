MODULE CMF_CTRL_OUTPUT_MOD
!==========================================================
!* PURPOSE: Control CaMa-Flood standard output file (binary / netCDF)  
!
!* CONTAINS:
! -- CMF_OUTPUT_NMLIST : Read output file info from namelist
! -- CMF_OUTPUT_INIT   : Create & Open standard output files
! -- CMF_OUTPUT_WRITE  : Write output to files
! -- CMF_OUTPUT_END    : Close standard output files
!
! (C) D.Yamazaki & E. Dutra  (U-Tokyo/FCUL)  Aug 2019
!
! Licensed under the Apache License, Version 2.0 (the "License");
!   You may not use this file except in compliance with the License.
!   You may obtain a copy of the License at: http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software distributed under the License is 
!  distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
! See the License for the specific language governing permissions and limitations under the License.
!==========================================================
! shared variables in module
USE PARKIND1,                ONLY: JPIM, JPRB, JPRM
USE YOS_CMF_INPUT,           ONLY: LOGNAM,  IFRQ_OUT
USE YOS_CMF_INPUT,           ONLY: CSUFBIN, CSUFVEC, CSUFPTH, CSUFCDF
USE YOS_CMF_INPUT,           ONLY: LPTHOUT, LDAMOUT, LLEVEE,  LWEVAP, LGDWDLY, LOUTINS,LROSPLIT
IMPLICIT NONE
!============================
SAVE
!*** NAMELIST/NOUTPUT/ from inputnam
CHARACTER(LEN=256)              ::  COUTDIR           ! OUTPUT DIRECTORY
CHARACTER(LEN=256)              ::  CVARSOUT          ! Comma-separated list of output variables to save 
CHARACTER(LEN=256)              ::  COUTTAG           ! Output Tag Name for each experiment
!
LOGICAL                         ::  LOUTVEC           ! TRUE FOR VECTORIAL OUTPUT, FALSE FOR NX,NY OUTPUT
LOGICAL                         ::  LOUTCDF           ! true for netcdf outptu false for binary
INTEGER(KIND=JPIM)              ::  NDLEVEL           ! NETCDF DEFLATION LEVEL 
!
LOGICAL                         ::  LOUTTXT           ! TRUE FOR Text output for some gauges
CHARACTER(LEN=256)              ::  CGAUTXT           ! List of Gauges (ID, IX, IY)
!
NAMELIST/NOUTPUT/ COUTDIR,CVARSOUT,COUTTAG,LOUTCDF,NDLEVEL,LOUTVEC,IFRQ_OUT,LOUTTXT,CGAUTXT
!
!*** local variables
INTEGER(KIND=JPIM), PARAMETER   :: NVARS=100          ! temporal output var number
INTEGER(KIND=JPIM)              :: NVARSOUT
INTEGER(KIND=JPIM)              :: IRECOUT            ! Output file irec
! Temporal aggregation according to CF conventions 1.7, Table E.1
CHARACTER(LEN=7), PARAMETER :: AGGREGATION_METHOD(3) = ["point  ", "mean   ", "maximum"]
!*** TYPE for output file    
TYPE TVAROUT
CHARACTER(LEN=256)              :: CVNAME             ! output variable name
CHARACTER(LEN=256)              :: CVLNAME            ! output variable long name
CHARACTER(LEN=256)              :: CVUNITS            ! output units
CHARACTER(LEN=256)              :: CFILE              ! output full path file name 
INTEGER(KIND=JPIM)              :: AGGREGATE = 1      ! index of AGGREGATION_METHODS, default is instantaneous/point
INTEGER(KIND=JPIM)              :: BINID              ! output binary output file ID
INTEGER(KIND=JPIM)              :: NCID               ! output netCDF output file ID
INTEGER(KIND=JPIM)              :: VARID              ! output netCDF output variable ID
INTEGER(KIND=JPIM)              :: TIMID              ! output netCDF time   variable ID 
INTEGER(KIND=JPIM)              :: IRECNC             ! Current time record for writting
END TYPE TVAROUT 
TYPE(TVAROUT),ALLOCATABLE       :: VAROUT(:)          ! output variable TYPE set

CONTAINS
!####################################################################
! -- CMF_OUTPUT_NMLIST : Read output file info from namelist
! -- CMF_OUTPUT_INIT   : Create & Open standard output files
! -- CMF_OUTPUT_WRITE  : Write output to files
! -- CMF_OUTPUT_END    : Close standard output files
! --
!####################################################################
SUBROUTINE CMF_OUTPUT_NMLIST
! reed setting from namelist
! -- Called from CMF_DRV_NMLIST
USE YOS_CMF_INPUT,      ONLY: CSETFILE,NSETFILE
USE CMF_UTILS_MOD,      ONLY: INQUIRE_FID
IMPLICIT NONE
!================================================
WRITE(LOGNAM,*) ""
WRITE(LOGNAM,*) "!---------------------!"

!*** 1. open namelist
NSETFILE=INQUIRE_FID()
OPEN(NSETFILE,FILE=CSETFILE,STATUS="OLD")
WRITE(LOGNAM,*) "CMF::OUTPUT_NMLIST: namelist OPEN in unit:", TRIM(CSETFILE), NSETFILE 

!*** 2. default value
COUTDIR="./"
CVARSOUT="outflw,storge,rivdph"
COUTTAG="_cmf"
LOUTCDF=.FALSE.
NDLEVEL=0
LOUTVEC=.FALSE.
IFRQ_OUT = 24                !! daily (24h) output
!
LOUTTXT=.FALSE.
CGAUTXT="None"

!*** 3. read namelist
REWIND(NSETFILE)
READ(NSETFILE,NML=NOUTPUT)

WRITE(LOGNAM,*)   "=== NAMELIST, NOUTPUT ==="
WRITE(LOGNAM,*)   "COUTDIR:  ", TRIM(COUTDIR)
WRITE(LOGNAM,*)   "CVARSOUT: ", TRIM(CVARSOUT)
WRITE(LOGNAM,*)   "COUTTAG:  ", TRIM(COUTTAG)

WRITE(LOGNAM,*)   "LOUTCDF:  ", LOUTCDF
IF( LOUTCDF )THEN
  WRITE(LOGNAM,*) "NDLEVEL:  ", NDLEVEL
ENDIF
if( LOUTVEC )THEN
  WRITE(LOGNAM,*) "LOUTVEC:  ", LOUTVEC
ENDIF
WRITE(LOGNAM,*)   "IFRQ_OUT  ", IFRQ_OUT

WRITE(LOGNAM,*)   "IFRQ_OUT  ", LOUTTXT
WRITE(LOGNAM,*)   "CGAUTXRT  ", CGAUTXT

CLOSE(NSETFILE)

WRITE(LOGNAM,*) "CMF::OUTPUT_NMLIST: end"

END SUBROUTINE CMF_OUTPUT_NMLIST
!####################################################################





!####################################################################
SUBROUTINE CMF_OUTPUT_INIT
! Initialize output module (create/open files)
! -- Called from CMF_DRV_INIT
USE YOS_CMF_INPUT,           ONLY: NX,NY
USE YOS_CMF_TIME,            ONLY: ISYYYY, ISMM,   ISDD,   ISHOUR, ISMIN
USE YOS_CMF_MAP,             ONLY: NSEQMAX,NPTHOUT,NPTHLEV,REGIONTHIS
USE CMF_UTILS_MOD,           ONLY: INQUIRE_FID
IMPLICIT NONE
!* Local variables 
CHARACTER(LEN=256)              :: CTIME, CTMP
INTEGER(KIND=JPIM)              :: JF,J,J0
CHARACTER(LEN=256)              :: CVNAMES(NVARS)
!================================================
WRITE(LOGNAM,*) ""
WRITE(LOGNAM,*) "!---------------------!"

WRITE(LOGNAM,*) "CMF::OUTPUT_INIT: check output variables"
!! Start by finding out # of output variables 
NVARSOUT=0
J0=1
DO J=1,LEN(TRIM(CVARSOUT))
  IF( (J>J0) .AND. (CVARSOUT(J:J) .EQ. ',') ) THEN
    CTMP=TRIM(ADJUSTL(CVARSOUT(J0:J-1)))
    IF (LEN(CTMP) > 0 ) THEN
      NVARSOUT=NVARSOUT+1
      CVNAMES(NVARSOUT)=CTMP
    ENDIF
    J0=J+1
  ENDIF
ENDDO
! Last one 
IF ( J0 <= LEN(TRIM(CVARSOUT)) ) THEN
  J=LEN(TRIM(CVARSOUT))
  CTMP=TRIM(ADJUSTL(CVARSOUT(J0:J)))
  IF (LEN(CTMP) > 0 ) THEN
     NVARSOUT=NVARSOUT+1
     CVNAMES(NVARSOUT)=CTMP
  ENDIF
ENDIF 

IF ( NVARSOUT == 0 ) THEN
  WRITE(LOGNAM,*) "CMF::OUTPUT_INIT: No output files will be produced!"
  RETURN
ENDIF 

ALLOCATE(VAROUT(NVARSOUT))
WRITE(CTIME,'(A14,I4.4,A1,I2.2,A1,I2.2,A1,I2.2,A1,I2.2)') 'seconds since ',ISYYYY,'-',ISMM,'-',ISDD,' ',ISHOUR,":",ISMIN

!* Loop on variables and create files 
DO JF=1,NVARSOUT
  WRITE(LOGNAM,*) "Creating output for variable:", TRIM( CVNAMES(JF) )
  SELECT CASE (CVNAMES(JF))
    CASE ('rivout')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='river discharge'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('rivsto')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='river storage'
      VAROUT(JF)%CVUNITS='m3'
    CASE ('rivdph')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='river depth'
      VAROUT(JF)%CVUNITS='m'
    CASE ('rivvel')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='river velocity'
      VAROUT(JF)%CVUNITS='m/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('fldout')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='floodplain discharge'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('fldsto')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='floodplain storage'
      VAROUT(JF)%CVUNITS='m3'
    CASE ('flddph')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='floodplain depth'
      VAROUT(JF)%CVUNITS='m'  
    CASE ('fldfrc')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='flooded fraction'
      VAROUT(JF)%CVUNITS='0-1'  
    CASE ('fldare')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='flooded area'
      VAROUT(JF)%CVUNITS='m2'

    CASE ('sfcelv')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='water surface elevation'
      VAROUT(JF)%CVUNITS='m'
    CASE ('totout')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='discharge (river+floodplain)'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('outflw')                   !! comparability for previous output name
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='discharge (river+floodplain)'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('totsto')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='total storage (river+floodplain)'
      VAROUT(JF)%CVUNITS='m3'
    CASE ('storge')                   !! comparability for previous output name
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='total storage (river+floodplain)'
      VAROUT(JF)%CVUNITS='m3'

    CASE ('pthflw')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='bifurcation channel discharge'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('pthout')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='net bifurcation discharge'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2

    CASE ('maxsto')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='daily maximum storage'
      VAROUT(JF)%CVUNITS='m3'
      VAROUT(JF)%AGGREGATE=3
    CASE ('maxflw')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='daily maximum discharge'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=3
    CASE ('maxdph')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='daily maximum river depth'
      VAROUT(JF)%CVUNITS='m' 
      VAROUT(JF)%AGGREGATE=3

    CASE ('runoff')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='Surface runoff'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('runoffsub')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='sub-surface runoff'
      VAROUT(JF)%CVUNITS='m3/s' 
      VAROUT(JF)%AGGREGATE=2

    CASE ('damsto')   !!! added
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='reservoir storage'
      VAROUT(JF)%CVUNITS='m3' 
    CASE ('daminf')   !!! added
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='reservoir inflow'
      VAROUT(JF)%CVUNITS='m3/s' 
      VAROUT(JF)%AGGREGATE=2

    CASE ('levsto')   !!! added
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='protected area storage'
      VAROUT(JF)%CVUNITS='m3' 
    CASE ('levdph')   !!! added
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='protected area depth'
      VAROUT(JF)%CVUNITS='m' 

    CASE ('gdwsto')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='ground water storage'
      VAROUT(JF)%CVUNITS='m3'
    CASE ('gwsto') !  ! old name. same as gdwsto
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='ground water storage'
      VAROUT(JF)%CVUNITS='m3'
    CASE ('gdwrtn') 
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='ground water discharge'
      VAROUT(JF)%CVUNITS='m3/s'  
      VAROUT(JF)%AGGREGATE=2
    CASE ('gwout')  !! old name. same as gdwrtn
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='ground water discharge'
      VAROUT(JF)%CVUNITS='m3/s'  
      VAROUT(JF)%AGGREGATE=2

    CASE ('wevap')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='water evaporation'
      VAROUT(JF)%CVUNITS='m3/s'
      VAROUT(JF)%AGGREGATE=2
    CASE ('outins')
      VAROUT(JF)%CVNAME=CVNAMES(JF)
      VAROUT(JF)%CVLNAME='instantaneous discharge'
      VAROUT(JF)%CVUNITS='m3/s' 

    CASE DEFAULT
    WRITE(LOGNAM,*) trim(CVNAMES(JF)), ' Not defined in CMF_CREATE_OUTCDF_MOD'
  END SELECT
  VAROUT(JF)%BINID=INQUIRE_FID()

  IF( LOUTCDF )THEN
    IF( REGIONTHIS==1 )THEN
      CALL CREATE_OUTCDF
    ENDIF
  ELSE
    CALL CREATE_OUTBIN
  ENDIF
END DO

IRECOUT=0  ! Initialize Output record to 1 (shared in netcdf & binary)

CONTAINS
!==========================================================
!+ CREATE_OUTBIN
!+ CREATE_OUTCDF
!==========================================================
SUBROUTINE CREATE_OUTBIN
IMPLICIT NONE
!================================================
IF( TRIM(VAROUT(JF)%CVNAME)=='pthflw' ) THEN   !! bifurcation channel
  IF( REGIONTHIS==1 )THEN
    VAROUT(JF)%CFILE=TRIM(COUTDIR)//TRIM(VAROUT(JF)%CVNAME)//TRIM(COUTTAG)//TRIM(CSUFPTH)
    OPEN(VAROUT(JF)%BINID,FILE=VAROUT(JF)%CFILE,FORM='UNFORMATTED',ACCESS='DIRECT',RECL=4*NPTHOUT*NPTHLEV)
    WRITE(LOGNAM,*) "output file opened in unit: ", TRIM(VAROUT(JF)%CFILE), VAROUT(JF)%BINID
  ENDIF
ELSEIF( LOUTVEC )THEN   !!  1D land only output
  VAROUT(JF)%CFILE=TRIM(COUTDIR)//TRIM(VAROUT(JF)%CVNAME)//TRIM(COUTTAG)//TRIM(CSUFVEC)
  OPEN(VAROUT(JF)%BINID,FILE=VAROUT(JF)%CFILE,FORM='UNFORMATTED',ACCESS='DIRECT',RECL=4*NSEQMAX)
  WRITE(LOGNAM,*) "output file opened in unit: ", TRIM(VAROUT(JF)%CFILE), VAROUT(JF)%BINID
ELSE                   !!  2D default map output
  IF( REGIONTHIS==1 )THEN
    VAROUT(JF)%CFILE=TRIM(COUTDIR)//TRIM(VAROUT(JF)%CVNAME)//TRIM(COUTTAG)//TRIM(CSUFBIN)
    WRITE(LOGNAM,*) "  -- ", TRIM(VAROUT(JF)%CFILE)
    OPEN(VAROUT(JF)%BINID,FILE=VAROUT(JF)%CFILE,FORM='UNFORMATTED',ACCESS='DIRECT',RECL=4*NX*NY)
    WRITE(LOGNAM,*) "output file opened in unit: ", TRIM(VAROUT(JF)%CFILE), VAROUT(JF)%BINID
  ENDIF
ENDIF


END SUBROUTINE CREATE_OUTBIN
!==========================================================
!+
!+
!+
!==========================================================
SUBROUTINE CREATE_OUTCDF
#ifdef UseCDF_CMF
USE YOS_CMF_INPUT,           ONLY: RMIS
USE YOS_CMF_MAP,             ONLY: D1LON, D1LAT
USE CMF_UTILS_MOD,           ONLY: NCERROR
USE NETCDF
IMPLICIT NONE
INTEGER(KIND=JPIM)  :: TIMEID,VARID,LATID,LONID
CHARACTER(LEN=32)   :: CMETH
!============
VAROUT(JF)%IRECNC=1 ! initialize record current writting record to 1 

!============
VAROUT(JF)%CFILE=TRIM(COUTDIR)//'o_'//TRIM(VAROUT(JF)%CVNAME)//TRIM(COUTTAG)//TRIM(CSUFCDF)
! Create file 
CALL NCERROR( NF90_CREATE(VAROUT(JF)%CFILE,NF90_NETCDF4,VAROUT(JF)%NCID),&
              'CREATING FILE:'//TRIM(VAROUT(JF)%CFILE) )
!=== set dimension ===
CALL NCERROR( NF90_DEF_DIM(VAROUT(JF)%NCID, 'time', NF90_UNLIMITED, TIMEID) )
CALL NCERROR( NF90_DEF_DIM(VAROUT(JF)%NCID, 'lat', NY, LATID) )
CALL NCERROR( NF90_DEF_DIM(VAROUT(JF)%NCID, 'lon', NX, LONID) )

!=== define variables ===
CALL NCERROR( NF90_DEF_VAR(VAROUT(JF)%NCID, 'lat', NF90_FLOAT, (/LATID/), VARID) )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VARID, 'long_name','latitude') )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VARID, 'units','degrees_north') )

CALL NCERROR( NF90_DEF_VAR(VAROUT(JF)%NCID, 'lon', NF90_FLOAT, (/LONID/), VARID) )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VARID, 'long_name','longitude') )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VARID, 'units','degrees_east') )

CALL NCERROR( NF90_DEF_VAR(VAROUT(JF)%NCID, 'time', NF90_DOUBLE, (/TIMEID/), VAROUT(JF)%TIMID) ) 
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VAROUT(JF)%TIMID, 'long_name','time') )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VAROUT(JF)%TIMID, 'units',CTIME) )

!===
CALL NCERROR( NF90_DEF_VAR(VAROUT(JF)%NCID, VAROUT(JF)%CVNAME, NF90_FLOAT, &
              (/LONID,LATID,TIMEID/), VAROUT(JF)%VARID,DEFLATE_LEVEL=NDLEVEL),     &
              'Creating Variable')

CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VAROUT(JF)%VARID, 'long_name', TRIM(VAROUT(JF)%CVLNAME)) )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VAROUT(JF)%VARID, 'units',     TRIM(VAROUT(JF)%CVUNITS)) )
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VAROUT(JF)%VARID, '_FillValue',RMIS) )
CMETH = 'time: ' // AGGREGATION_METHOD(VAROUT(JF)%AGGREGATE)
CALL NCERROR( NF90_PUT_ATT(VAROUT(JF)%NCID, VAROUT(JF)%VARID, 'cell_method', TRIM(CMETH)) )


CALL NCERROR( NF90_ENDDEF(VAROUT(JF)%NCID) )

!=== put lon lat info ===
CALL NCERROR ( NF90_INQ_VARID(VAROUT(JF)%NCID,'lon',VARID),'getting id' )
CALL NCERROR( NF90_PUT_VAR(VAROUT(JF)%NCID,VARID,D1LON))

CALL NCERROR ( NF90_INQ_VARID(VAROUT(JF)%NCID,'lat',VARID),'getting id' )
CALL NCERROR( NF90_PUT_VAR(VAROUT(JF)%NCID,VARID,D1LAT))

WRITE(LOGNAM,*) 'CFILE: ',TRIM(VAROUT(JF)%CFILE),' CVAR:',TRIM(VAROUT(JF)%CVNAME),&
                ' CLNAME: ',TRIM(VAROUT(JF)%CVLNAME),' CUNITS: ',TRIM(VAROUT(JF)%CVUNITS)
WRITE(LOGNAM,*) 'OPEN IN UNIT: ',VAROUT(JF)%NCID
#endif
END SUBROUTINE CREATE_OUTCDF
!==========================================================

END SUBROUTINE CMF_OUTPUT_INIT
!####################################################################





!####################################################################
SUBROUTINE CMF_OUTPUT_WRITE
!======
USE CMF_UTILS_MOD,           ONLY: vecD2mapR
! save results to output files
! -- Called either from "MAIN/Coupler" or CMF_DRV_ADVANCE
USE YOS_CMF_INPUT,      ONLY: NX, NY, LOUTINI
USE YOS_CMF_MAP,        ONLY: NSEQMAX, NPTHOUT, NPTHLEV, REGIONTHIS
USE YOS_CMF_TIME,       ONLY: JYYYYMMDD, JHHMM, JHOUR, JMIN, KSTEP
USE YOS_CMF_PROG,       ONLY: P2RIVSTO,     P2FLDSTO,     P2GDWSTO, &
                            & P2DAMSTO,     P2LEVSTO,     D2COPY       !!! added
USE YOS_CMF_DIAG,       ONLY: D2RIVDPH,     D2FLDDPH,     D2FLDFRC,     D2FLDARE,     D2SFCELV,     D2STORGE, &
                            & D2OUTFLW_oAVG, D2RIVOUT_oAVG, D2FLDOUT_oAVG, D2PTHOUT_oAVG, D1PTHFLW_oAVG,  &
                            & D2RIVVEL_oAVG, D2GDWRTN_oAVG, D2RUNOFF_oAVG, D2ROFSUB_oAVG, D2WEVAPEX_oAVG, &
                            & D2OUTFLW_oMAX, D2STORGE_oMAX, D2RIVDPH_oMAX, &
                            & D2DAMINF_oAVG, D2OUTINS, D2LEVDPH   !!! added
#ifdef UseMPI_CMF
USE CMF_CTRL_MPI_MOD,   ONLY: CMF_MPI_AllReduce_R2MAP, CMF_MPI_AllReduce_R1PTH
#endif
IMPLICIT NONE
INTEGER(KIND=JPIM)          :: JF
REAL(KIND=JPRB),POINTER     :: D2VEC(:,:) ! point data location to output
!*** LOCAL
REAL(KIND=JPRM)             :: R2OUT(NX,NY)
REAL(KIND=JPRM)             :: R1POUT(NPTHOUT,NPTHLEV)
!================================================
WRITE(LOGNAM,*) ""
WRITE(LOGNAM,*) "!---------------------!"

!*** 0. check date:hour with output frequency
IF ( MOD(JHOUR,IFRQ_OUT)==0 .and. JMIN==0 ) THEN             ! JHOUR: end of time step , NFPPH: output frequency (hour)

  !*** 1. update IREC & calc average variable
  IRECOUT=IRECOUT+1 
  WRITE(LOGNAM,*) 'CMF::OUTPUT_WRITE: write at time: ', JYYYYMMDD, JHHMM, IRECOUT

  !*** 2. check variable name & allocate data to pointer DVEC
  DO JF=1,NVARSOUT
    SELECT CASE (VAROUT(JF)%CVNAME)
      CASE ('rivsto')
        D2COPY=REAL(P2RIVSTO,KIND=JPRB)  !! convert Double to Single precision when using SinglePrecisionMode 
        D2VEC => D2COPY  !!   (Storage variables are kept as Float64 in SinglePrecisionMode)
      CASE ('fldsto')
        D2COPY=REAL(P2FLDSTO,KIND=JPRB)
        D2VEC => D2COPY

      CASE ('rivout')
        D2VEC => D2RIVOUT_oAVG
      CASE ('rivdph')
        D2VEC => D2RIVDPH
      CASE ('rivvel')
        D2VEC => D2RIVVEL_oAVG
      CASE ('fldout')
        D2VEC => D2FLDOUT_oAVG

      CASE ('flddph')
        D2VEC => D2FLDDPH
      CASE ('fldfrc')
        D2VEC => D2FLDFRC
      CASE ('fldare')
        D2VEC => D2FLDARE
      CASE ('sfcelv')
        D2VEC => D2SFCELV

      CASE ('totout')
        D2VEC => D2OUTFLW_oAVG
      CASE ('outflw')            !!  compatibility for previous file name
        D2VEC => D2OUTFLW_oAVG
      CASE ('totsto')
        D2VEC => D2STORGE
      CASE ('storge')            !!  compatibility for previous file name
        D2VEC => D2STORGE

      CASE ('pthout')
        IF( .not. LPTHOUT ) CYCLE
        D2VEC => D2PTHOUT_oAVG
      CASE ('pthflw')
        IF( .not. LPTHOUT ) CYCLE
      CASE ('maxflw')
        D2VEC =>  D2OUTFLW_oMAX
      CASE ('maxdph')
        D2VEC =>  D2RIVDPH_oMAX
      CASE ('maxsto')
        D2VEC =>  D2STORGE_oMAX

      CASE ('outins')
        IF( .not. LOUTINS ) CYCLE
        D2VEC =>  D2OUTINS

      CASE ('gwsto')
        IF( .not. LGDWDLY ) CYCLE
        D2COPY=REAL(P2GDWSTO,KIND=JPRB)
        D2VEC =>  D2COPY
      CASE ('gdwsto')
        IF( .not. LGDWDLY ) CYCLE
        D2COPY=REAL(P2GDWSTO,KIND=JPRB)
        D2VEC =>  D2COPY
      CASE ('gwout')
        IF( .not. LGDWDLY ) CYCLE
        D2VEC =>  D2GDWRTN_oAVG
      CASE ('gdwrtn')
        IF( .not. LGDWDLY ) CYCLE
        D2VEC =>  D2GDWRTN_oAVG

      CASE ('runoff')             !!  compatibility for previous file name
        D2VEC =>  D2RUNOFF_oAVG  
      CASE ('runoffsub')           !!  compatibility for previous file name
        IF( .not. LROSPLIT ) CYCLE
        D2VEC =>  D2ROFSUB_oAVG  
      CASE ('rofsfc')
        D2VEC =>  D2RUNOFF_oAVG
      CASE ('rofsub')
        D2VEC =>  D2ROFSUB_oAVG
      CASE ('wevap')
        IF( .not. LWEVAP ) CYCLE
        D2VEC => D2WEVAPEX_oAVG

      CASE ('damsto')   !!! added
        IF( .not. LDAMOUT ) CYCLE
        D2COPY=REAL(P2DAMSTO,KIND=JPRB)
        D2VEC => D2COPY
      CASE ('daminf')   !!! added
        IF( .not. LDAMOUT ) CYCLE
        D2VEC =>  d2daminf_oAVG

      CASE ('levsto')   !!! added
        IF( .not. LLEVEE ) CYCLE
        D2COPY=REAL(P2LEVSTO,KIND=JPRB)
        D2VEC => D2COPY
      CASE ('levdph')   !!! added
        IF( .not. LLEVEE ) CYCLE
        D2VEC =>  D2LEVDPH

      CASE DEFAULT
!        WRITE(LOGNAM,*) VAROUT(JF)%CVNAME, ' Not defined in CMF_OUTPUT_MOD'
!#ifdef IFS_CMF
!        CALL ABORT
!#endif
    END SELECT   !! variable name select

    IF( KSTEP==0 .and. LOUTINI )THEN  !! write storage only when LOUTINI specified
      IF ( .not. LOUTCDF ) CYCLE
      IF ( VAROUT(JF)%CVNAME/='rivsto' .and. VAROUT(JF)%CVNAME/='fldsto' .and. VAROUT(JF)%CVNAME/='gwsto' ) CYCLE
    ENDIF

!! convert 1Dvector to 2Dmap
    IF( VAROUT(JF)%CVNAME/='pthflw' ) THEN  !! usual 2D map variable
      CALL vecD2mapR(D2VEC,R2OUT)             !! MPI node data is gathered by vecP2mapR
#ifdef UseMPI_CMF
      CALL CMF_MPI_AllReduce_R2MAP(R2OUT)
#endif
    ELSE
      IF( .not. LPTHOUT ) CYCLE
      R1POUT(:,:)=REAL(D1PTHFLW_oAVG(:,:))
#ifdef UseMPI_CMF
      CALL CMF_MPI_AllReduce_R1PTH(R1POUT)
#endif
    ENDIF

    !*** 3. write D2VEC to output file
    IF ( LOUTCDF ) THEN
      IF ( REGIONTHIS==1 ) CALL WRTE_OUTCDF  !! netCDFG
    ELSE
      IF( VAROUT(JF)%CVNAME=='pthflw' ) THEN
        IF ( REGIONTHIS==1 ) CALL WRTE_OUTPTH(VAROUT(JF)%BINID,IRECOUT,R1POUT)        !! 1D bifu channel
      ELSE
        IF( LOUTVEC )THEN
          CALL WRTE_OUTVEC(VAROUT(JF)%BINID,IRECOUT,D2VEC)         !! 1D vector (optional)
        ELSE
          IF ( REGIONTHIS==1 ) CALL WRTE_OUTBIN(VAROUT(JF)%BINID,IRECOUT,R2OUT)         !! 2D map
        ENDIF
      ENDIF
    ENDIF
  END DO

  WRITE(LOGNAM,*) 'CMF::OUTPUT_WRITE: end'


ENDIF



!==========================================================
CONTAINS
!+ WRTE_OUTBIN
!+ WRTE_OUTPTH
!+ WRTE_OUTVEC
!+ WRTE_OUTCDF
!==========================================================
SUBROUTINE WRTE_OUTBIN(IFN,IREC,R2OUTDAT)
IMPLICIT NONE
!*** INPUT
INTEGER(KIND=JPIM),INTENT(IN)   :: IFN                 !! FILE NUMBER
INTEGER(KIND=JPIM),INTENT(IN)   :: IREC                !! RECORD
REAL(KIND=JPRM)                 :: R2OUTDAT(NX,NY)
!================================================
WRITE(IFN,REC=IREC) R2OUTDAT

END SUBROUTINE WRTE_OUTBIN
!==========================================================
!+
!+
!+
!==========================================================
SUBROUTINE WRTE_OUTPTH(IFN,IREC,R2OUTDAT)
IMPLICIT NONE
!*** INPUT
INTEGER(KIND=JPIM),INTENT(IN)   :: IFN                 !! FILE NUMBER
INTEGER(KIND=JPIM),INTENT(IN)   :: IREC                !! RECORD
REAL(KIND=JPRM)                 :: R2OUTDAT(NPTHOUT,NPTHLEV)
!================================================
WRITE(IFN,REC=IREC) R2OUTDAT

END SUBROUTINE WRTE_OUTPTH
!==========================================================
!+
!+
!+
!==========================================================
SUBROUTINE WRTE_OUTVEC(IFN,IREC,D2OUTDAT)
IMPLICIT NONE
!*** INPUT
INTEGER(KIND=JPIM),INTENT(IN)   :: IFN                 !! FILE NUMBER
INTEGER(KIND=JPIM),INTENT(IN)   :: IREC                !! RECORD
REAL(KIND=JPRB),INTENT(IN)      :: D2OUTDAT(NSEQMAX,1) !! OUTPUT DATA
!*** LOCAL
REAL(KIND=JPRM)                 :: R2OUTDAT(NSEQMAX,1)
!================================================
R2OUTDAT(:,:)=REAL(D2OUTDAT(:,:))
WRITE(IFN,REC=IREC) R2OUTDAT

END SUBROUTINE WRTE_OUTVEC
!==========================================================
!+
!+
!+
!==========================================================
SUBROUTINE WRTE_OUTCDF
#ifdef UseCDF_CMF
USE NETCDF 
USE YOS_CMF_TIME,            ONLY: KMINSTART,KMINNEXT
USE CMF_UTILS_MOD,           ONLY: NCERROR
IMPLICIT NONE
REAL(KIND=JPRB)                 :: XTIME ! seconds since start of the run !

!================================================
XTIME=REAL( (KMINNEXT-KMINSTART),JPRB) *60._JPRB      !! for netCDF
CALL NCERROR( NF90_PUT_VAR(VAROUT(JF)%NCID,VAROUT(JF)%TIMID,XTIME,(/VAROUT(JF)%IRECNC/)) )

CALL NCERROR( NF90_PUT_VAR(VAROUT(JF)%NCID,VAROUT(JF)%VARID,R2OUT(1:NX,1:NY),(/1,1,VAROUT(JF)%IRECNC/),(/NX,NY,1/)) )

! update IREC
VAROUT(JF)%IRECNC=VAROUT(JF)%IRECNC+1

! Comment out this as it slows down significantly the writting in the cray  
!CALL NCERROR( NF90_SYNC(VAROUT(JF)%NCID) )  
#endif
END SUBROUTINE WRTE_OUTCDF 
!==========================================================

END SUBROUTINE CMF_OUTPUT_WRITE
!####################################################################





!####################################################################
SUBROUTINE CMF_OUTPUT_END
! Finalize output module (close files)
! -- Called from CMF_DRV_END
#ifdef UseCDF_CMF
USE NETCDF
USE CMF_UTILS_MOD,           ONLY: NCERROR
#endif
USE YOS_CMF_MAP,             ONLY: REGIONTHIS
IMPLICIT NONE
! Local variables
INTEGER(KIND=JPIM)              :: JF
!================================================
WRITE(LOGNAM,*) ""
WRITE(LOGNAM,*) "!---------------------!"
WRITE(LOGNAM,*) "CMF::OUTPUT_END: finalize output module"

IF( REGIONTHIS==1 )THEN
  IF (LOUTCDF) THEN
#ifdef UseCDF_CMF
    DO JF=1,NVARSOUT
      CALL NCERROR( NF90_CLOSE(VAROUT(JF)%NCID))
      WRITE(LOGNAM,*) "Output netcdf output unit closed:",VAROUT(JF)%NCID
    ENDDO
#endif
  ELSE !! binary output
    DO JF=1,NVARSOUT
      CLOSE(VAROUT(JF)%BINID)
      WRITE(LOGNAM,*) "Output binary output unit closed:",VAROUT(JF)%BINID
    ENDDO
    IF( LOUTVEC )THEN
      CALL WRTE_mapR2vecD  !! write map-vector conversion file
    ENDIF
  ENDIF
ENDIF

WRITE(LOGNAM,*) "CMF::OUTPUT_END: end"


CONTAINS
!==========================================================
!+ WRTE_mapR2vecD
!+
!+
!==========================================================
SUBROUTINE WRTE_mapR2vecD       !! 1D sequence vector informtion required to convert MPI distributed vector output to 2D map
USE YOS_CMF_INPUT,      ONLY: TMPNAM
USE YOS_CMF_MAP,        ONLY: I1SEQX, I1SEQY, NSEQMAX
USE CMF_UTILS_MOD,      ONLY: INQUIRE_FID
IMPLICIT NONE
!* local variable
CHARACTER(LEN=256)         :: CFILE1
!================================================
IF( LOUTVEC )THEN
  CFILE1='./ind_xy'//TRIM(CSUFVEC)

  WRITE(LOGNAM,*) "LOUTVEC: write mapR2vecD conversion table", TRIM(CFILE1)

  TMPNAM=INQUIRE_FID()
  OPEN(TMPNAM,FILE=CFILE1,FORM='UNFORMATTED',ACCESS='DIRECT',RECL=4*NSEQMAX)
  WRITE(TMPNAM,REC=1) I1SEQX
  WRITE(TMPNAM,REC=2) I1SEQY
  CLOSE(TMPNAM)
ENDIF

END SUBROUTINE WRTE_mapR2vecD
!================================================


END SUBROUTINE CMF_OUTPUT_END
!####################################################################



!####################################################################
SUBROUTINE CMF_OUTTXT_WRTE
USE YOS_CMF_DIAG,       ONLY: D2OUTFLW
USE YOS_CMF_TIME,       ONLY: IYYYYMMDD,ISYYYY
USE YOS_CMF_MAP,        ONLY: I2VECTOR
USE CMF_UTILS_MOD,      ONLY: INQUIRE_FID

! local
INTEGER(KIND=JPIM)                  :: GID, GIX, GIY, GISEQ
CHARACTER(len=256),SAVE             :: GNAME

INTEGER(KIND=JPIM),SAVE             :: IGAUGE, NGAUGE, NGAUGEX
INTEGER(KIND=JPIM),ALLOCATABLE,SAVE :: WriteID(:), WriteISEQ(:)
CHARACTER(len=9),ALLOCATABLE,SAVE   :: WriteName(:)
REAL(KIND=JPRB),ALLOCATABLE,SAVE    :: WriteOut(:)

! File IO
INTEGER(KIND=JPIM),SAVE             :: LOGOUTTXT
CHARACTER(len=4),SAVE               :: cYYYY
CHARACTER(len=256),SAVE             :: CLEN, CFMT
CHARACTER(len=256),SAVE             :: COUTTXT
LOGICAL,SAVE                        :: IsOpen
DATA IsOpen       /.FALSE./

! ======

IF( LOUTTXT )THEN

  IF( .not. IsOpen)THEN
    IsOpen=.TRUE.

    NGAUGEX=0
    LOGOUTTXT=INQUIRE_FID()
    OPEN(LOGOUTTXT,FILE=CGAUTXT,FORM='formatted',STATUS='old')
    READ(LOGOUTTXT,*) NGAUGE
    DO IGAUGE=1, NGAUGE
      READ(LOGOUTTXT,*) GID, GNAME, GIX, GIY
      IF( I2VECTOR(GIX,GIY)>0 )THEN
        NGAUGEX=NGAUGEX+1
      ENDIF
    END DO
    CLOSE(LOGOUTTXT)

    ALLOCATE( WriteID(NGAUGEX),WriteISEQ(NGAUGEX),WriteOut(NGAUGEX),WriteName(NGAUGEX))

    NGAUGEX=0
    OPEN(LOGOUTTXT,FILE=CGAUTXT,FORM='formatted',STATUS='old')
    READ(LOGOUTTXT,*) NGAUGE
    DO IGAUGE=1, NGAUGE
      READ(LOGOUTTXT,*) GID, GNAME, GIX, GIY
      IF( I2VECTOR(GIX,GIY)>0 )THEN
        NGAUGEX=NGAUGEX+1
        WriteID(NGAUGEX)  =GID
        WriteName(NGAUGEX)=TRIM(GNAME)
        WriteISEQ(NGAUGEX)=I2VECTOR(GIX,GIY)
      ENDIF
    END DO
    CLOSE(LOGOUTTXT)

    ! ============
    WRITE(CYYYY,'(i4.4)') ISYYYY
    COUTTXT='./outtxt-'//TRIM(cYYYY)//'.txt'

    LOGOUTTXT=INQUIRE_FID()
    OPEN(LOGOUTTXT,FILE=COUTTXT,FORM='formatted')

    WRITE(CLEN,'(i0)') NGAUGE
    CFMT="(i10,"//TRIM(CLEN)//"(i10))"
    WRITE(LOGOUTTXT,CFMT) NGAUGEX, ( WriteID(IGAUGE),IGAUGE=1,NGAUGEX )

    CFMT="(i10,"//TRIM(CLEN)//"(x,a9))"
    WRITE(LOGOUTTXT,CFMT) NGAUGEX, ( WriteName(IGAUGE),IGAUGE=1,NGAUGEX )


    CFMT="(i10,"//TRIM(CLEN)//"(f10.2))"
  ENDIF

  DO IGAUGE=1, NGAUGEX
    GISEQ=WriteISEQ(IGAUGE)
    WriteOut(IGAUGE) = D2OUTFLW(GISEQ,1)
  END DO
  
  WRITE(LOGOUTTXT,CFMT) IYYYYMMDD, ( WriteOUT(IGAUGE),IGAUGE=1,NGAUGEX )

ENDIF

END SUBROUTINE CMF_OUTTXT_WRTE
!####################################################################

END MODULE CMF_CTRL_OUTPUT_MOD
