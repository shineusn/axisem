!========================
module source
!========================

use global_parameters
use data_mesh
use data_source
use data_time
use data_proc
use data_io

implicit none

public :: compute_stf,compute_stf_t,compute_src,read_sourceparams
private
contains

!@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

!-----------------------------------------------------------------------------
subroutine read_sourceparams
!
! sourceparams.dat :
!
!1.E20               magnitude (Nm)
!'dipole'            excitation type: 'monopole', 'dipole', 'quadpole'
!'mxz'               'explosion','mxx_p_myy','mzz','vertforce' (MONOPOLE)
!                    'mxz', 'myz', 'xforce', 'yforce'          (DIPOLE)
!                    'mxy', 'mxx_m_myy'                        (QUADRUPOLE)
!344.034             source depth [km]
!'gauss_1'           source time function: 'dirac_0', 'gauss_0', 'gauss_1' 
!                    (1st deriv), 'gauss_2' (2nd)
!100.0               dominant source period [s]; put 0 if to be 
!                    calculated automatically from mesh/model
!
!-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  
  real(kind=realkind) :: srclat
  character(len=30) :: junk,eventname
  character(len=30) :: src_header(12)
  real(kind=realkind) :: time_shift
  integer :: i,j

  rot_src = .false.

!=========================
  if (src_file_type=='separate' .or. src_file_type=='sourceparams') then 
!=========================

     open(unit=20000,file='sourceparams.dat',POSITION='REWIND',status='old')
     read(20000,*)(Mij(i),i=1,6)
     read(20000,*)src_type(1)
     read(20000,*)src_type(2)
     read(20000,*)
     read(20000,*)
     read(20000,*)src_depth
     src_depth=src_depth*1000. ! in meters
     read(20000,*)srccolat
     read(20000,*)srclon
     srccolat=srccolat*pi/180.d0
     srclon=srclon*pi/180.d0

     read(20000,*)stf_type
     close(20000)
!    -----------------------------------------------------------------
     if (num_simul==4) then ! moment tensor elements
!    -----------------------------------------------------------------
        if (isim==1) then 
           src_type(1)='monopole'
           src_type(2)='mzz'
           magnitude=Mij(1)
        elseif (isim==2) then
           src_type(1)='monopole'
           src_type(2)='mxx_p_myy'
           magnitude=Mij(2)+Mij(3)
        elseif (isim==3) then
           src_type(1)='dipole'
           src_type(2)='mxz'
           magnitude=Mij(4)
        elseif (isim==4) then
           src_type(1)='quadpole'
           src_type(2)='mxy'
           magnitude=Mij(6)
        else 
           write(6,*)'ERROR: simulation number not recognized:',isim,num_simul
           stop
        endif

!    -----------------------------------------------------------------
     elseif (num_simul==2) then ! single forces
!    -----------------------------------------------------------------
        if  (isim==1) then 
           src_type(1)='monopole'
           src_type(2)='vertforce'
        elseif (isim==2) then
           src_type(1)='dipole'
           src_type(2)='xforce'
        else
           write(6,*)procstrg,&
                'ERROR: simulation number not recognized:',isim,num_simul
           stop
        endif

!    -----------------------------------------------------------------
     elseif (num_simul==1 ) then ! moment tensor /single force component
!    -----------------------------------------------------------------
        if (lpr) then 
           write(6,*)
           write(6,*)'  One simulation for one source!'
        endif

        if (src_type(2)=='mzz') then           
            magnitude=Mij(1)
            Mij=0.
            Mij(1)=magnitude  
        elseif (src_type(2)=='mxx_p_myy') then
            magnitude=(Mij(2)+Mij(3))/2.
            Mij=0.
            Mij(2:3)=magnitude/2.
        elseif (src_type(2)=='mxz') then
            magnitude=Mij(4)
            Mij=0.
           Mij(4)=magnitude
        elseif (src_type(2)=='myz') then
           magnitude=Mij(5)
           Mij=0.
           Mij(5)=magnitude
        elseif (src_type(2)=='mxy') then
           magnitude=Mij(6)
           Mij=0.
           Mij(6)=magnitude
        elseif (src_type(2)=='mxx_m_myy') then
           magnitude=(Mij(2)-Mij(3))/2.
           Mij=0.
           Mij(2)=magnitude/2.
           Mij(3)=-magnitude/2. 
        elseif (src_type(2)=='explosion') then 
           magnitude=(Mij(1)+Mij(2)+Mij(3))/3.
           Mij=0.
           Mij(1:3)=magnitude
        elseif (src_type(2)=='vertforce' .or. src_type(2)=='xforce' .or. src_type(2)=='yforce') then
           magnitude=1.
        endif

!    -----------------------------------------------------------------
     else
!    -----------------------------------------------------------------
        write(6,*)procstrg,'ERROR: Unrecognized number of simulations:',num_simul
        write(6,*)procstrg,'       Choose 1: moment tensor element or force'
        write(6,*)procstrg,'       Choose 2: all single forces'
        write(6,*)procstrg,'       Choose 4: full moment tensor'
        stop
!    -----------------------------------------------------------------
     endif
!    -----------------------------------------------------------------

     if (magnitude<smallval) then 
        write(6,*)' .... ERROR: Inconsistency between magnitude given by moment tensor and source type!'
        write(6,*)' .... check sourceparams.dat and make sure that the source type has a non-zero moment tensor entry.'
        write(6,*)' .... source type & magnitude:',src_type(2),magnitude
        write(6,*)' .... moment tensor:',(Mij(i),i=1,6)
        stop
     endif

!=========================
  elseif (src_file_type=='cmtsolut') then
!=========================
     
     if(lpr) write(6,*)'  reading CMTSOLUTION file....'
     open(unit=20000,file='CMTSOLUTION',POSITION='REWIND',status='old')
     read(20000,*)stf_type,src_header(1:12)
     read(20000,*)junk,junk,eventname
     read(20000,*)junk,junk,time_shift 
     read(20000,*)junk,junk,enforced_period
     read(20000,*)junk,srclat
     read(20000,*)junk,srclon  
     read(20000,*)junk,src_depth
     read(20000,*)junk,Mij(1) !Mrr
     read(20000,*)junk,Mij(2) !Mtt
     read(20000,*)junk,Mij(3) !Mpp
     read(20000,*)junk,Mij(4) !Mrt
     read(20000,*)junk,Mij(5) !Mrp
     read(20000,*)junk,Mij(6) !Mtp
     close(20000)

     if (lpr) then 
        write(6,*)'  CMT header: ',(trim(src_header(i)//' '),i=1,12)
        write(6,*)'  event name: ',trim(eventname)
     endif
     if (srclon<=zero) srclon=srclon+360.d0 
     srccolat = 90.d0 - srclat
     srclon = srclon*pi/180.0
     srccolat = srccolat*pi/180.0
     src_depth = src_depth*1000.
     if (trim(stf_type)/='gauss_0' .and. trim(stf_type)/='gauss_1' .and. trim(stf_type)/='gauss_2' .and. &
          trim(stf_type)/='heavis' .and. trim(stf_type)/='quheavi' ) then
        if (lpr) then 
           write(6,*)'  ...setting source time function to dirac by default!'
           write(6,*)'     if you wish to choose another stf, '
           write(6,*)'     prepend the first line with the stf name, i.e before: ',trim(stf_type)
           write(6,*)'     add gauss_0, gauss_1, gauss_2, heavis, or quheavi.'
           write(6,*)
        endif
        stf_type='dirac_0'

     else 
        if (lpr)write(6,*)'  source time function:',stf_type
     endif

     if ( Mij(1)/=zero .and. sum(abs(Mij(2:6)))<smallval*abs(Mij(1)) ) then 
        src_type(1)='monopole'
        src_type(2)='mzz'
        magnitude=Mij(1)
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!'

     elseif ( abs(Mij(2)-Mij(3))<smallval*abs(Mij(2)) .and. abs(Mij(1))<smallval*abs(Mij(2)) .and. &
          sum(abs(Mij(4:6)))<smallval*abs(Mij(2)) ) then 
        src_type(1)='monopole'
        src_type(2)='mxx_p_myy'
        magnitude=(Mij(2)+Mij(3))/2.
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!'

     elseif ( abs(Mij(2)-Mij(3))<smallval*abs(Mij(2)) .and. abs(Mij(2)-Mij(1))<smallval*abs(Mij(2)) .and. &
          sum(abs(Mij(4:6)))<smallval*abs(Mij(2)) ) then 
        src_type(1)='monopole'
        src_type(2)='explosion'
        magnitude=sum(Mij(1:3))/3.
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!'

     elseif ( Mij(4)/=zero .and. sum(abs(Mij(1:3))) + sum(abs(Mij(5:6)))<smallval*abs(Mij(4)) ) then 
        src_type(1)='dipole'
        src_type(2)='mxz'
        magnitude=Mij(4)
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!' 

     elseif ( Mij(5)/=zero .and. (sum(abs(Mij(1:4))) + abs(Mij(6)))<smallval*abs(Mij(5)) ) then 
        src_type(1)='dipole'
        src_type(2)='myz'
        magnitude=Mij(5)
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!' 

     elseif ( Mij(6)/=zero .and. sum(abs(Mij(1:5)))<smallval*abs(Mij(6)) ) then 
        src_type(1)='quadpole'
        src_type(2)='mxy'
        magnitude=Mij(6)
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!'

     elseif ( abs(Mij(2)+Mij(3))<smallval*abs(Mij(2)) .and. abs(Mij(1))<smallval*abs(Mij(2)) .and. &
          sum(abs(Mij(4:6)))<smallval*abs(Mij(2)) ) then 
        src_type(1)='quadpole'
        src_type(2)='mxx_m_myy'
        magnitude=(Mij(2)-Mij(3))/2.
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!'

     else
        if (lpr) write(6,*)'  Moment tensor has multiple non-zero entries... therefore doing separate simulations.. '
        magnitude=Mij(1)
        src_type(1) = 'monopole'
        src_type(2) = 'mzz'
        if (lpr) write(6,*)'    simulating a '//src_type(2)//' source instead of CMTSOLUTION!'
     endif

     ! Magnitude in CMTSOLUTION is given in dyn*cm... rescaling:
     magnitude = magnitude/1.E7
     Mij=Mij/1.E7

     open(unit=899,file='Data/moment_tensor.dat')
     write(899,*)(Mij(i),i=1,3)
     write(899,*)(Mij(i),i=4,6)
     close(899)

!=========================
  elseif (src_file_type=='finfault') then
!=========================

     if (lpr) write(6,*) ' Simulating a finite fault'
     open(unit=20000,file='finite_fault.dat',POSITION='REWIND',status='old')
     READ(20000,*)junk
     read(20000,*)fflt_num
     read(20000,*)fflt_stf_name
     read(20000,*)fflt_nt,fflt_dt
     read(20000,*)fflt_scalarmoment
     read(20000,*)junk
     read(20000,*)junk
     read(20000,*)junk
     allocate(fflt_lat(fflt_num),fflt_lon(fflt_num),fflt_depth(fflt_num))
     allocate(fflt_strike(fflt_num),fflt_dip(fflt_num),fflt_rake(fflt_num))
     do i=1,fflt_num
        read(20000,*)fflt_lat(i),fflt_lon(i),fflt_depth(i),fflt_strike(i),fflt_dip(i),fflt_rake(i)
     enddo
     if (fflt_num==1) then 
        read(20000,*)src_type(1)
        read(20000,*)src_type(2)
     endif
     close(20000)
     num_simul = fflt_num

 ! conversions
     allocate(fflt_theta(fflt_num),fflt_phi(fflt_num),fflt_r(fflt_num),fflt_Mij(6,fflt_num))
     fflt_theta = (90.-fflt_lat)*pi/180.
     do i=1,fflt_num
        if (fflt_lon(i)<=zero) fflt_lon(i)=fflt_lon(i) + 360.d0 
     enddo
     fflt_phi = fflt_lon*pi/180.
     fflt_r = router-fflt_depth*1.d3
     fflt_strike = fflt_strike*pi/180.
     fflt_dip = fflt_dip*pi/180.
     fflt_rake = fflt_rake*pi/180.
     fflt_Mij(1,:) = sin(2.d0*fflt_dip)*sin(fflt_rake) !Mrr
     fflt_Mij(2,:) = -sin(fflt_dip)*cos(fflt_rake)*sin(2.d0*fflt_strike) - & ! Mtt
                      sin(2.d0*fflt_dip)*(sin(2.d0*fflt_strike))**2*sin(fflt_rake)
     fflt_Mij(3,:) = sin(fflt_dip)*cos(fflt_rake)*sin(2.d0*fflt_strike) - & ! Mpp
                     sin (2.d0*fflt_dip)*(cos(2.d0*fflt_strike))**2*sin(fflt_rake)   
     fflt_Mij(4,:) = -sin(fflt_rake)*sin(fflt_strike)*cos(2.d0*fflt_dip) - & ! Mrt
                      cos(fflt_dip)*cos(fflt_rake)*cos(fflt_strike)     
     fflt_Mij(5,:) = cos(fflt_strike)*sin(fflt_rake)*cos(2.d0*fflt_dip) -  & ! Mrp
                     cos(fflt_dip)*cos(fflt_rake)*sin(fflt_strike)       
     fflt_Mij(6,:) = sin(fflt_dip)*cos(fflt_rake)*cos(2.d0*fflt_strike) +  &  !Mtp
                     half*sin(2.d0*fflt_dip)*sin(2.d0*fflt_strike)*sin(fflt_rake)

     fflt_Mij = fflt_Mij*fflt_scalarmoment

     deallocate(fflt_lat,fflt_lon,fflt_depth,fflt_strike,fflt_dip,fflt_rake)
     if (lpr) then
        write(6,*)'  fflt: number of points in finite fault:',fflt_num
        write(6,*)'  fflt: min/max radius [km]:',minval(fflt_r)/1000.,maxval(fflt_r)/1000.
        write(6,*)'  fflt: min/max colatitude (deg):',minval(fflt_theta)*180./pi,maxval(fflt_theta)*180./pi
        write(6,*)'  fflt: min/max longitude (deg):',minval(fflt_phi)*180./pi,maxval(fflt_phi)*180./pi       
        write(6,*)'  fflt: moment tensors:'
        do i=1,fflt_num
           write(6,*)'  fflt:',(fflt_Mij(j,i),j=1,6)
        enddo
        if (fflt_num==1) write(6,*)'  fflt: src_type: ',trim(src_type(1)),trim(src_type(2))
     endif

     if (fflt_num>1) then 
        write(6,*)"  Haven't implemented the finite fault option to run multiple simulations in serial or parallel."
        write(6,*)"  Please resubmit by specifying 'finfault' as the second argument to the submit script."
        stop
     endif

! prepare number of simulations, rotations, etc

stop
!=========================
  elseif (src_file_type=='deliverg') then
!=========================

     write(6,*) ' deliverg SOURCE FILE TYPE NOT IMPLEMENTED YET!'
     stop

!=========================
  else 
!=========================

     write(6,*) 'ERROR: source file type undefined:',src_file_type
     stop
!=========================
  endif
  !=========================
  
  if (srccolat/=0.d0 .or. srclon/=0.d0 ) then
     write(6,*)
     write(6,*)procstrg, '  Source not along the axis!'
     write(6,*)procstrg,'  ...therefore applying rotations to source and receivers.'
     rot_src=.true.
  endif

  if (lpr) then
     write(6,*)''
     write(6,*)'  *****************GIVEN SOURCE PARAMETERS*****************'
     write(6,11)'   Magnitude [Nm]:       ',magnitude
     write(6,13)'   Excitation type:         ',src_type(1),src_type(2)
     write(6,11)'   Depth [km]:           ',src_depth/1000.
     write(6,11)'   Colat. [deg]:         ',real(srccolat*180./pi)
     write(6,11)'   Long. [deg]:          ',real(srclon*180./pi)
     write(6,14)'   Source time function:  ',stf_type
     write(6,12)'   Dom. period mesh [s]:     ',period
     write(6,*)'  *********************************************************'
     write(6,*)''
     call flush(6)
  endif

  if (srcvic) then 
     if (src_type(2)/='explosion') then
        if (lpr) then
           write(6,*)
           write(6,7)'0000000000000000 OFF-TOPIC WARNING 000000000000000000000000'
           write(6,7)'00                                                       00'
           write(6,7)'00 Analyt. rad. for non-explos. sources not implemented  00'
           write(6,7)'00             therefore turning it off...               00'
           write(6,7)'00                                                       00'
           write(6,7)'00000000000000000000000000000000000000000000000000000000000'
           write(6,*)
        endif
        srcvic=.false.
     endif
  endif

7 format(08x,a62)

11 format(a28,1pe15.3)
12 format(a28,f9.4)
13 format(a28,2(a12))
14 format(a28,a12)

end subroutine read_sourceparams
!=============================================================================

!-----------------------------------------------------------------------------
subroutine compute_stf

integer :: i

  allocate(stf(1:niter))

  select case(stf_type)
  case('dirac_0')
    call delta_src ! there are hidden treasures in this routine...discrete Dirac's.
  case('dirac_1')
    call delta_src_old 
  case('gauss_0')
    call gauss
  case('gauss_1')
    call gauss_d
  case('gauss_2')
    call gauss_dd
  case('quheavi')
    call quasiheavi
  case('heavis') ! a wiggly wavelet with a sharp boxcar power spectrum
    call heavis
  case default
    write(6,*)' source time function non existant:',stf_type
    stop
   end select

  if (lpr) then
     open(299,file=datapath(1:lfdata)//'/stf.dat',status='replace',action='write')
     do i=1,niter
        write(299,*)real(i)*real(deltat),real(stf(i))
     enddo
     close(299)
  endif

end subroutine compute_stf

!=============================================================================

!-----------------------------------------------------------------------------
subroutine compute_stf_t(nstf_t,t,stf_t)
! These *_t routines are needed by the symplectic time integration schemes. 
! Eventually there should be only one type, point- or array-wise.

integer, intent(in)           :: nstf_t
double precision, intent(in)  :: t(1:nstf_t)
double precision, intent(out) :: stf_t(1:nstf_t)


  select case(stf_type)
  case('dirac_0')
    call delta_src_t(nstf_t,t,stf_t)
  case('gauss_0')
    call gauss_t(nstf_t,t,stf_t)
  case('gauss_1')
    call gauss_d_t(nstf_t,t,stf_t)
  case('gauss_2')
    call gauss_dd_t(nstf_t,t,stf_t)
  case('quheavi')
    call quasiheavi_t(nstf_t,stf_t)
!af
  case('heavis')
    call heavis_t(nstf_t,stf_t)
  case default
    write(6,*)' source time function non existant:',stf_type
    stop
   end select

end subroutine compute_stf_t
!=============================================================================

!-----------------------------------------------------------------------------
subroutine compute_src

use data_mesh_preloop
use utlity
use commun, ONLY : broadcast_int,broadcast_dble

integer                          :: iel_src2,ipol_src2,jpol_src2
real(kind=realkind), allocatable :: source_term(:,:,:,:)
real(kind=realkind), allocatable :: point_source(:,:,:)
integer                          :: ipol,jpol,ielem,k
double precision                 :: s,z,r,theta

  allocate(source_term(0:npol,0:npol,1:nel_solid,1:3))
!af crucial for gfortran
  source_term = 0. 
!
  zsrc=router-src_depth

  if (lpr) then
     write(6,*)
     write(6,*)'  *****************************************'
     write(6,*)'     Welcome to the source term calculator '
     write(6,*)'  *****************************************'
     write(6,*)
     write(6,*)'  locating the source....'
  endif
  write(69,*)
  write(69,*)'    L O O K I N G   F O R   T H E   S O U R C E '

  call find_srcloc(iel_src2,ipol_src2,jpol_src2)

  if (have_src .and. mynum/=0) then 
     write(6,*)
     write(6,*)'PROBLEM with the source location!'
     write(6,*)'I have the source and am processor',mynum
     write(6,*)'...when source should always be on the northern axis (mynum=0)'
     stop
  endif

  call broadcast_int(iel_src,0)
  call broadcast_int(ipol_src,0)
  call broadcast_int(jpol_src,0)
  call broadcast_dble(zsrc,0)

  poletype: select case(src_type(1))

! MONOPOLE
  case ('monopole') poletype
     if (lpr) write(6,*)'  computing MONOPOLE Source with...'

     select case (src_type(2))
     case('vertforce') 
        if (lpr) write(6,*)'  ...vertical single force'
        allocate(point_source(0:npol,0:npol,1:nel_solid))
        call define_bodyforce(point_source,iel_src2,ipol_src2,jpol_src2)
        source_term(:,:,:,3)=point_source/(two*pi)
        deallocate(point_source)

     case default
        if (lpr) write(6,*)'  ...moment tensor elements for ',src_type(2)

        call define_moment_tensor(iel_src2,ipol_src2,jpol_src2,source_term)
        source_term=source_term/(two*pi)
     end select

     ! DIPOLE
  case ('dipole') poletype
     if (lpr) write(6,*)'  computing DIPOLE Source with...'

     select case(src_type(2))
     case ('xforce','yforce')
        allocate(point_source(0:npol,0:npol,1:nel_solid))
        if (lpr) write(6,*)'  ...horizontal single ',src_type(2)
        call define_bodyforce(point_source,iel_src2,ipol_src2,jpol_src2)
        source_term(:,:,:,1)=point_source/pi
        deallocate(point_source)

     case default
        if (lpr) write(6,*)'  ...moment tensor elements for ',src_type(2)
        call define_moment_tensor(iel_src2,ipol_src2,jpol_src2,source_term)
        source_term=source_term/pi

     end select

     ! QUADRUPOLE
  case ('quadpole') poletype
     if (lpr) write(6,*)'  computing QUADRUPOLE Source with...'
     if (lpr) write(6,*)'  ...moment tensor elements for ',src_type(2)
     call define_moment_tensor(iel_src2,ipol_src2,jpol_src2,source_term)
     source_term=source_term/pi

  case default
     write(6,*)'WE ONLY SUPPORT MONOPOLES, DIPOLES, &
          &QUADRUPOLES, AND NOT ',src_type(1)
     call flush(6)
     stop

  end select poletype

! if I don't have the source
  if (.not. have_src) then 
     source_term = zero
     write(69,*)
     write(69,*)"******  I  D O N ' T   H A V E   T H E   S O U R C E *******"
     write(69,*)
  endif
 
! write all elements containing non-zero source term components to file
  if (have_src) then
     open(619,file=infopath(1:lfinfo)//'/src_term.dat'//appmynum) 
     open(621,file=infopath(1:lfinfo)//'/src_term_norm1.dat'//appmynum) 
     open(622,file=infopath(1:lfinfo)//'/src_term_norm2.dat'//appmynum) 
     open(623,file=infopath(1:lfinfo)//'/src_term_norm3.dat'//appmynum) 
     open(6200,file=infopath(1:lfinfo)//'/src_term_allcomp.dat'//appmynum)
     do ielem=1,nel_solid
        if  (maxval(abs(source_term(:,:,ielem,:))) /= zero) then
           do ipol=0,npol
              do jpol=0,npol
                call compute_coordinates(s,z,r,theta,ielsolid(ielem),ipol,jpol)
                write(619,12)ielem,ipol,jpol,source_term(ipol,jpol,ielem,1), &
                  source_term(ipol,jpol,ielem,2),source_term(ipol,jpol,ielem,3)
                write(621,13)s/router,z/router,source_term(ipol,jpol,ielem,1)/&
                      maxval(abs(source_term(:,:,:,1)))*7.
                write(622,13)s/router,z/router,source_term(ipol,jpol,ielem,2)/&
                      maxval(abs(source_term(:,:,:,2)))*7.
                write(623,13)s/router,z/router,source_term(ipol,jpol,ielem,3)/&
                      maxval(abs(source_term(:,:,:,3)))*7.
              enddo
           enddo
        endif
     enddo
12 format(i9,2(i2),3(1pe12.4))
13 format(3(1pe12.4))
  endif !have_src

  close(619)
  close(621)
  close(622)
  close(623)

  call flush(6198)
  call flush(6199)
  call flush(6200)

! construct source term array that only lives on nonzero elements (max. 6)
  source_term_el = zero
  k = 0 
  if (have_src) then
     do ielem = 1, nel_solid
        if ( maxval(abs(source_term(:,:,ielem,:))) > zero) then
           k=k+1
           ielsrc(k)=ielem
           source_term_el(:,:,k,:) = source_term(:,:,ielem,:)
        endif
     enddo
  endif
  nelsrc = k

  deallocate(source_term)

  if (nelsrc > 6) then 
     write(6,*)procstrg,'PROBLEM with source term element count!'
     write(6,*)procstrg,nelsrc, &
               'elements with nonzero entries found when 6 is max.'
     stop
  endif

  if (have_src) then
     write(6,*)'  number of elements with non-zero source term:',nelsrc
     write(6,*)
     write(6,*)'  *********************************'
     write(6,*)'        End of source term calculator'
     write(6,*)'  *********************************'
  endif

  write(69,*)'  *********************************'
  write(69,*)'        End of source term calculator'
  write(69,*)'  *********************************'

end subroutine compute_src
!=============================================================================

!-----------------------------------------------------------------------------
subroutine find_srcloc(iel_src2,ipol_src2,jpol_src2)

use data_mesh_preloop
use utlity
use commun, ONLY: pmin,barrier,broadcast_int,psum_int

integer, intent(out) :: iel_src2,ipol_src2,jpol_src2
double precision     :: s,z,r,theta,mydzsrc,zsrcout,dzsrc
integer              :: ielem,ipol,jpol,count_src_procs

! find depth that is closest to desired value zsrc

  dzsrc=10.d0*router

! Only allow sources in the solid region, fixated to northern axis.
  do ielem = 1, nel_solid
     do ipol = 0, npol
        do jpol = 0, npol
           call compute_coordinates(s,z,r,theta,ielsolid(ielem),ipol,jpol)
           if ( s== zero .and. abs(z-zsrc) < dzsrc .and. z>=zero) then 
              zsrcout=z
              dzsrc=abs(z-zsrc)
              iel_src=ielem
              ipol_src=ipol
              jpol_src=jpol
              iel_src2=ielem
              ipol_src2=ipol
              jpol_src2=jpol
           elseif (s== zero .and. abs(z-zsrc) == dzsrc .and. z>=zero) then 
              write(69,15) ielem,ipol,jpol,z/1000.
              iel_src2=ielem
              ipol_src2=ipol
              jpol_src2=jpol
           endif
        enddo
     enddo
  enddo
15 format('  found a second point with same distance:',i6,i3,i3,1pe13.3)

! Make sure only closest processor has source
  mydzsrc=dzsrc
  have_src=.true.

  if (nproc> 1) then
     mydzsrc = pmin(mydzsrc)
     if (mydzsrc < dzsrc) have_src=.false.

! Check how many/which processors have the source
     count_src_procs=0
     if (have_src) count_src_procs=1
     count_src_procs=psum_int(count_src_procs)

     if (count_src_procs>1) then 
        if (lpr) then 
           write(6,*)
           write(6,*)'PROBLEM with source & processors!'
           write(6,*)'More than one processor has the source:'
        endif
        if (have_src) write(6,*)procstrg,'has it.'
        stop
     elseif (count_src_procs==0) then 
        if (lpr) then
           write(6,*)
           write(6,*)'PROBLEM with source & processors!'
           write(6,*)'No processor has the source.'
        endif
        stop
     endif 
  endif !nproc>1

!- - - - - - - - - -
  if (have_src) then
!- - - - - - - - - -
     if (ipol_src /= 0) then
        write(6,*)'PROBLEM: Source should be on axis, i.e. ipol_src=0, but:'
        write(6,*)'Source location: ielem,ipol,jpol:', &
                             ielsolid(iel_src),ipol_src,jpol_src
        call flush(6)
        stop
     endif

     if (thetacoord(ipol_src,jpol_src,ielsolid(iel_src)) /= zero) then
        write(6,*)'PROBLEM: Source should be on the axis, hence theta=0, but:'
        write(6,*)'Source indices ielem,ipol,jpol:', &
                  ielsolid(iel_src),ipol_src,jpol_src
        write(6,*)'s,r,theta',scoord(ipol_src,jpol_src,ielsolid(iel_src)), &
                              rcoord(ipol_src,jpol_src,ielsolid(iel_src)), &
                              thetacoord(ipol_src,jpol_src,ielsolid(iel_src))
        call flush(6)
        stop
     endif

     write(6,*)'  ',procstrg,' found it:'
     write(6,*)'    depth asked for [km]:',(router-zsrc)/1000.d0
     write(6,*)'    depth offered   [km]:',(router-zsrcout)/1000.d0
     write(6,*)'    difference      [km]:',dzsrc/1000.d0

     write(69,*)'  ',procstrg,' found it:'
     write(69,*)'    depth asked for [km]:',(router-zsrc)/1000.d0
     write(69,*)'    depth offered   [km]:',(router-zsrcout)/1000.d0
     write(69,*)'    difference      [km]:',dzsrc/1000.d0
     write(69,*)'    source element and jpol index:', iel_src,jpol_src

     if (iel_src2 /=iel_src) then
         write(6,*)'    SECOND source element and jpol index:',  &
                            iel_src2,jpol_src2
         call flush(6)     
         write(69,*)'    SECOND source element and jpol index:',  &
                            iel_src2,jpol_src2
         call flush(6)     
     endif

     if (.not. have_axis) then 
        write(6,*)procstrg,'Problem: something wrong with processor'
        write(6,*)'Have axis:',have_axis
        write(6,*)'Have source:',have_src
        stop
     endif

     zsrc = zsrcout

!- - - - - - - - - -
  endif
!- - - - - - - - - -

end subroutine find_srcloc
!=============================================================================

!-----------------------------------------------------------------------------
subroutine quasiheavi
!Allocated variable stf was used without being set to some sensible value before
integer :: i

stf = 0.
  do i=seis_it,niter
!     t=dble(i)*deltat-shift_fact*t_0
!    stf(i) = 0.5d0*(1.0d0+erf(t/t_0))
!af for pgf erf is not known
     stf(i) = 1.
  enddo

  stf=stf*magnitude

end subroutine quasiheavi
!=============================================================================

!-----------------------------------------------------------------------------
subroutine gauss

integer :: i
real(kind=realkind) :: t,decay,shift_fact

  decay=3.5d0
  shift_fact=1.5d0

  do i=1,niter
     t=dble(i)*deltat
     stf(i) = dexp(-( (decay/t_0*(t-shift_fact*t_0))**2) )
  enddo

  stf=stf * magnitude * decay / t_0 / dsqrt(pi)

end subroutine gauss
!=============================================================================


!-----------------------------------------------------------------------------
subroutine gauss_d

integer :: i
real(kind=realkind) :: t,decay,shift_fact

  decay=3.5d0
  shift_fact=1.5d0
  
  do i=1,niter
     t=dble(i)*deltat
     stf(i) = -two*(decay/t_0)**2*(t-shift_fact*t_0) * &
          dexp(-( (decay/t_0*(t-shift_fact*t_0))**2) )
  enddo

! max/min at t=t_0*(shift_fact +- sqrt(0.5)/decay)
! and corresponding max(stf)= +- decay/t_0*sqrt(two)*exp(-half)

  stf=stf/( decay/t_0*sqrt(two)*exp(-half) )*magnitude

end subroutine gauss_d
!=============================================================================

!-----------------------------------------------------------------------------
subroutine gauss_dd

integer :: i
real(kind=realkind) :: t,decay,shift_fact

  decay=3.5d0
  shift_fact=1.5d0

  do i=1,niter
     t=dble(i)*deltat
     stf(i) = (decay/t_0)**2 *( two* (decay/t_0)**2 *(t-shift_fact*t_0)**2-1)*&
               dexp(-( (decay/t_0*(t-shift_fact*t_0))**2) )
  enddo

! max/min at t=t_0*(shift_fact +- sqrt(1.5)/decay)
! and corresponding max(stf)= +- two*((decay/t_0)**2*exp(-three/two)
! and at t=shift_fact*t_0

  stf=stf/( two*((decay/t_0)**2)*exp(-three/two) )*magnitude

end subroutine gauss_dd
!
!=============================================================================
!
subroutine heavis
double precision, dimension(:), allocatable :: myt
integer :: it
double precision, dimension(:), allocatable :: mystf

allocate(myt(niter))
myt(:)=0.
allocate(mystf(niter))
mystf(:)=0.
do it=1, niter
 myt(it)=real(it)*deltat
enddo
call heavis_t(niter,mystf)
stf=real(mystf)
end subroutine heavis

!-----------------------------------------------------------------------------
subroutine delta_src_old

  stf(1:niter) = zero
  if (lpr) then 
     write(6,*)
     write(6,*)'  Source delta-dirac ignites at first seismogram sample [s]:',&
              seis_it*deltat
     write(6,*)'  WARNING: Remember to subtract this at postprocessing stage!'
  endif
  stf(seis_it) = magnitude / deltat
!  if (lpr) call write_convolve_routine

end subroutine delta_src_old
!=============================================================================



!-----------------------------------------------------------------------------
subroutine delta_src
! approximate discrete dirac
 integer :: i,j
 double precision :: a
 character(len=6) :: dirac_approx(6),discrete_choice
 double precision,allocatable :: stftmp(:),timetmp(:)

! this is the choice of discrete dirac
 discrete_choice = '1dirac'

  if (lpr) write(6,*)'Approximate Dirac',niter
  allocate(stftmp(1:niter),timetmp(1:niter))

  stf(1:niter) = zero

!  if (lpr) then
!    write(6,*)
!     write(6,*)'  Source delta-dirac ignites at first seismogram sample [s]:',&
!              seis_it*deltat
!     write(6,*)'  WARNING: Remember to subtract this at postprocessing stage!'
!  endif
!  stf(seis_it) = magnitude

  a=period/15.
!  a=deltat*10.

  dirac_approx = ['cauchy','caulor','sincfc','gaussi','triang','1dirac']
  if (lpr) write(6,*)'  Approximate Diracs:',dirac_approx
  do j=1,6
     stftmp = 0.
     if (lpr) write(6,*)'Approximation type:',trim(dirac_approx(j))
     if (lpr) open(unit=60,file='Info/approx_dirac_'//trim(dirac_approx(j))//'.dat')
     do i=1,niter
        t=dble(i)*deltat
        timetmp(i) = t
        if (dirac_approx(j)=='cauchy') then 
           ! Cauchy phi function
           stftmp(i) = 1./a * exp(-abs((t-deltat)/a))

        elseif (dirac_approx(j)=='caulor') then
           ! Cauchy Lorentz distribution
           stftmp(i) = 1./pi *a/ (a**2 + t**2)

        elseif (dirac_approx(j)=='sincfc') then
           ! sinc function
           stftmp(i) = 1./(a*pi) * ( sin(t/a)/(t/a)  )

        elseif (dirac_approx(j)=='gaussi') then
           ! Gaussian
           stftmp(i) = 1./(a*sqrt(pi)) * exp(-(t/a)**2)   

        elseif (dirac_approx(j)=='triang') then
           ! triangular
           if (abs(t)<=a/2. ) then 
              stftmp(i) = 2./a - 4./a**2 *abs(t)
           else
              stftmp(i) = 0.
           endif

        elseif (dirac_approx(j)=='1dirac') then 
           ! old Dirac, 1 non-zero point
           if (i==seis_it) stftmp(i) = 1./deltat
        else
           write(6,*)mynum,'does not know discrete Dirac ',trim(dirac_approx(j))
           stop
        endif
        if (lpr)   write(60,*)t,magnitude*stftmp(i)   
     enddo
     if (lpr) write(6,*)'integral over stf:',trim(dirac_approx(j)),sum(stftmp)*deltat
     if (lpr)  close(60)
     if (trim(dirac_approx(j))==trim(discrete_choice)) stf(1:niter) = stftmp(1:niter) 
  enddo

stf=stf*magnitude

if (lpr)  then 
   open(unit=61,file='Info/chosen_approx_dirac_'//trim(discrete_choice)//'.dat')
   do i=1,niter
     write(61,*)timetmp(i),stf(i)
  enddo
  close(61)
endif
deallocate(timetmp,stftmp)

!  if (lpr) call write_convolve_routine

end subroutine delta_src
!=============================================================================


!-----------------------------------------------------------------------------
subroutine write_convolve_routine

logical :: mono_log
integer :: nrec

open(99999,file='receivers.dat',POSITION='REWIND',status='old',action='read')
    read(99999,*)nrec
close(99999)

mono_log=.false.
if (src_type(1)=='monopole') mono_log=.true.

open(unit=101,file=datapath(1:lfdata)//'/input_convolve.txt',status='replace',action='write')
  write(101,*)seis_it*deltat
  write(101,*)nrec
  write(101,*)niter/seis_it
  write(101,*)mono_log
  write(101,*)'seisantipode1.dat'
 if (.not. mono_log) write(101,*)'seisantipode2.dat'
  write(101,*)'seisantipode3.dat'
  write(101,*)'seisepicenter1.dat'
 if (.not. mono_log) write(101,*)'seisepicenter2.dat'
  write(101,*)'seisepicenter3.dat'
  write(101,*)'seisequator1.dat'
 if (.not. mono_log) write(101,*)'seisequator2.dat'
  write(101,*)'seisequator3.dat'
  write(101,*)'seishypocenter1.dat'
 if (.not. mono_log) write(101,*)'seishypocenter2.dat'
  write(101,*)'seishypocenter3.dat'
close(101)

write(6,*)
write(6,*)"  wrote post-processing convolution info into 'input_convolve.txt'"
write(6,*)"  use 'convolve_with_stf.f90' to convolve:"
write(6,*)"  f90 convolve_with_stf.f90 -o convolve_with_stf.x"
write(6,*)"  ./convolve_with_stf.csh <period> "

end subroutine write_convolve_routine
!=============================================================================

!-----------------------------------------------------------------------------
subroutine gauss_t(nstf_t,t,stf_t)

integer, intent(in)           :: nstf_t
double precision, intent(in)  :: t(nstf_t)
double precision, intent(out) :: stf_t(nstf_t)
integer                       :: i
double precision              :: decay,shift_fact

  decay=3.5d0
  shift_fact=1.5d0

  do i=1,nstf_t
     stf_t(i) = dexp(-( (decay/t_0*(t(i)-shift_fact*t_0))**2) )
  enddo

  stf_t = stf_t * magnitude * decay / ( t_0 * sqrt(pi) )

end subroutine gauss_t
!=============================================================================


!-----------------------------------------------------------------------------
subroutine gauss_d_t(nstf_t,t,stf_t)

integer, intent(in)              :: nstf_t
double precision, intent(in)  :: t(nstf_t)
double precision, intent(out) :: stf_t(nstf_t)
integer                          :: i
double precision              :: decay,shift_fact

  decay=3.5d0
  shift_fact=1.5d0
  
  do i=1,nstf_t
     stf_t(i) = -two*(decay/t_0)**2*(t(i)-shift_fact*t_0) * &
          dexp(-( (decay/t_0*(t(i)-shift_fact*t_0))**2) )
  enddo

  stf_t=stf_t/( decay/t_0*dsqrt(two)*dexp(-half) )*magnitude

end subroutine gauss_d_t
!=============================================================================

!-----------------------------------------------------------------------------
subroutine gauss_dd_t(nstf_t,t,stf_t)

integer, intent(in)              :: nstf_t
double precision, intent(in)  :: t(nstf_t)
double precision, intent(out) :: stf_t(nstf_t)
integer                          :: i
double precision              :: decay,shift_fact

  decay=3.5d0
  shift_fact=1.5d0

  do i=1,nstf_t
     stf_t(i) = (decay/t_0)**2 *(two*(decay/t_0)**2 *(t(i)- &
                 shift_fact*t_0)**2-1)*&
                 dexp(-( (decay/t_0*(t(i)-shift_fact*t_0))**2) )
  enddo

  stf_t=stf_t/( two*((decay/t_0)**2)*exp(-three/two) )*magnitude

end subroutine gauss_dd_t
!=============================================================================
subroutine heavis_t(nstf_t,stf_t)

integer, intent(in) :: nstf_t
double precision, intent(out) :: stf_t(nstf_t)
integer :: nstep2
complex*16, dimension(:), allocatable :: spectre
integer :: j,i,istat
double precision:: freq,wt,tmax,t1,t2
complex*16 :: dphi
!
double precision :: f1h,f2h,f3h,f4h,timezero
!
!f1h=0.20E-2
!f2h=0.6E-2
!f3h=2.50E-2
!f4h=3.33333333E-2
!timezero=500. 

! TNM: trying this generically.. 
f1h=0.20E-2
f2h=0.6E-2
f3h=1./(0.8*t_0)
f4h=1./(0.6*t_0)
timezero=300. 
!
stf_t(:) = 0.
nstep2=int(2.d0**(int(log(dble(nstf_t))/log(2.d0))+1))
write(6,*) 'nstep2=',nstep2
allocate(spectre(nstep2))
spectre(:)=cmplx(0.,0.) 
do j=1, nstep2
 if (j<=nstep2/2) then
  freq=(j-1)/(deltat*nstep2)
 else if (j==nstep2/2+1) then
  freq=1/(2.d0*deltat)
 else
  freq=-(nstep2-j+1)/(deltat*nstep2)
 endif
 dphi=exp(-2.d0*pi*freq*timezero*cmplx(0.d0,1.d0))
 call wtcoef(abs(freq),f1h,f2h,f3h,f4h,wt)
!         if (j/=1) spectre(j)=wt*dphi/cmplx(0._DP,freq*2._DP*PI)
 if (j/=1) spectre(j)=wt*dphi
end do  
!do j=1,nstep2
! write(22,*) j, abs(spectre(j))
!end do
call dfour1(spectre,nstep2,1)

stf_t(:)=real(spectre(1:nstf_t))/nstep2/deltat
stf_t(:)=magnitude*stf_t/maxval(abs(stf_t))

!the first time steps are set to zero
      tmax=nstep2*deltat
      t1=0.d0
      t2=timezero/5.d0
      do i=1,nstf_t
         call wtcoef((i-1)*deltat,t1,t2,tmax,tmax,wt)
         stf_t(i)=stf_t(i)*wt
      enddo
 deallocate(spectre,stat=istat)
 if (istat/=0) stop 'time_function deallocate error'

end subroutine heavis_t
!----------------------------------------------------------------------
  subroutine wtcoef(f,f1,f2,f3,f4,wt)
    implicit none
!
    double precision, intent(in) ::  f,f1,f2,f3,f4
    double precision, intent(out)::  wt
!
    if (f3.gt.f4) stop 'wtcoef: f3>f4 '
    if (f1.gt.f2) stop 'wtcoef: f1>f2 '
    if (f.le.f3.and.f.ge.f2) then
       wt=1.0
    else if (f.gt.f4.or.f.lt.f1 ) then
       wt=0.0
    else if (f.gt.f3.and.f.le.f4) then
       wt=0.5*(1.0+cos(pi*(f-f3)/(f4-f3)))
    else if (f.ge.f1.and.f.lt.f2) then
       wt=0.5*(1.0+cos(pi*(f-f2)/(f2-f1)))
    endif
  end subroutine wtcoef
!----------------------------------------------------------------------
                                                                                    
!-----------------------------------------------------------------------------
subroutine delta_src_t(nstf_t,t,stf_t)

integer, intent(in)              :: nstf_t
double precision, intent(in)  :: t(nstf_t)
double precision, intent(out) :: stf_t(nstf_t)

  stf_t(1:nstf_t)=zero
!if (t(1)>5.d0*deltat .and. t(1)<6.d0*deltat) stf_t(1)=magnitude

  if (t(1)>3.d0*deltat .and. t(1)<=4.d0*deltat) stf_t(nstf_t)=magnitude
  if (t(1)>=4.d0*deltat .and. t(1)<5.d0*deltat) stf_t(1)=magnitude

!
! a ramp like this: /\
!
!if (t(1)>3.d0*deltat .and. t(1)<4.d0*deltat) then 
!  do i=1,nstf_t
!   stf_t(i)=magnitude/deltat*(t(i)-3.d0*deltat)
!  enddo
!endif
!
!if (t(1)>4.d0*deltat .and. t(1)<5.d0*deltat) then 
!  do i=1,nstf_t
!   stf_t(i)=magnitude/deltat*(-t(i)+5.d0*deltat)
!  enddo
!endif

end subroutine delta_src_t
!=============================================================================

!-----------------------------------------------------------------------------
subroutine quasiheavi_t(nstf_t,stf_t)
! Added this one, was not implemented before. SCS 050710

integer, intent(in)              :: nstf_t
double precision, intent(out) :: stf_t(nstf_t)
!integer                          :: i
!double precision              :: decay,shift_fact

!  decay=3.5d0
!  shift_fact=1.5d0
  
!  do i=1,nstf_t
!     stf_t(i) = -two*(decay/t_0)**2*(t(i)-shift_fact*t_0) * &
!          dexp(-( (decay/t_0*(t(i)-shift_fact*t_0))**2) )
!  enddo
!  stf_t=stf_t/( decay/t_0*dsqrt(two)*dexp(-half) )*magnitude
stf_t=0.
  stf_t(seis_it:nstf_t) = magnitude

end subroutine quasiheavi_t
!=============================================================================


!-----------------------------------------------------------------------------
subroutine define_bodyforce(f,iel_src2,ipol_src2,jpol_src2)

use data_mesh_preloop
use utlity
use commun

real(kind=realkind), intent(out) :: f(0:npol,0:npol,nel_solid)
integer, intent(in)              :: iel_src2,ipol_src2,jpol_src2
integer                          :: liel_src,lipol_src,ljpol_src,ipol,jpol,i
double precision                 :: s,z,r,theta
character(len=16)                :: fmt1
integer                          :: nsrcelem

  nsrcelem = 1
  if (iel_src2/=iel_src) nsrcelem=2
  f(:,:,:) = zero

!()()()()()()()()()()()()()
  if (have_src) then
     f(ipol_src,jpol_src,iel_src) = one
     f(ipol_src2,jpol_src2,iel_src2) = one
  endif
!()()()()()()()()()()()()()

! check whether Lamb or wot
  call compute_coordinates(s,z,r,theta,ielsolid(iel_src),ipol_src,jpol_src)
  if ( abs(z-router) < smallval*router .and. lpr) &
       write(6,*)"  ...actually Lamb's Problem"
  call flush(6)

! assembly
  call comm2d(f,nel_solid,1,'solid')

!()()()()()()()()()()()()()
  if (have_src) then
!()()()()()()()()()()()()()

! write out the source element
     fmt1 = "(K(1pe12.3))"
     write(fmt1(2:2),'(i1.1)') npol+1

     write(69,*)
     write(69,*)'  *^*^*^*^**^*^*^* The single-force source term *^*^*^*^*^^*^'

     liel_src=iel_src
     lipol_src=ipol_src
     ljpol_src=jpol_src

     do i =1,nsrcelem
        if (i==2) then
           liel_src=iel_src2
           lipol_src=ipol_src2
           ljpol_src=jpol_src2
        endif

        write(69,*)'iel,jpol,r:',liel_src,ljpol_src, &
             rcoord(lipol_src,ljpol_src,ielsolid(liel_src))/1.d3
        write(69,*)'North| s-dir -->'
        do jpol=npol,0,-1
           write(69,fmt1)(f(ipol,jpol,liel_src),ipol=0,npol)
        enddo
        write(69,*)
        write(69,*)
     enddo

!()()()()()()()()()()()()()
  endif ! have_src
!()()()()()()()()()()()()()

end subroutine define_bodyforce
!=============================================================================

!-----------------------------------------------------------------------------
subroutine define_moment_tensor(iel_src2,ipol_src2,jpol_src2,source_term)
!
! Defines the moment tensor elements for the given source type in all 
! elements having non-zero source contributions,
! using pointwise derivatives of arbitrary scalar functions.
!
!-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

use data_mesh_preloop
use data_spec, ONLY : shp_deri_k

use apply_masks
use utlity
use pointwise_derivatives
use commun

integer, intent(in)              :: iel_src2,ipol_src2,jpol_src2
real(kind=realkind), intent(out) :: source_term(0:npol,0:npol,nel_solid,3)
integer                          :: liel_src,lipol_src,ljpol_src

real(kind=realkind), allocatable :: ws(:,:,:),dsws(:,:,:)
real(kind=realkind), allocatable :: ws_over_s(:,:,:),dzwz(:,:,:)
real(kind=realkind), allocatable :: ds(:),dz(:)

integer                          :: ielem,ipol,jpol,i,nsrcelem
double precision                 :: s,z,r,theta,r1,r2
logical                          :: oldway
character(len=16)                :: fmt1

  allocate(ws(0:npol,0:npol,1:nel_solid),dsws(0:npol,0:npol,1:nel_solid))
  allocate(ws_over_s(0:npol,0:npol,1:nel_solid))
  allocate(dzwz(0:npol,0:npol,1:nel_solid))
  allocate(ds(0:npol),dz(0:npol))

  oldway=.TRUE.
  
  dzwz(:,:,:) = zero
  dsws(:,:,:) = zero
  ws_over_s(:,:,:) = zero
  source_term(:,:,:,:) = zero

  liel_src=iel_src
  lipol_src=ipol_src
  ljpol_src=jpol_src

  nsrcelem = 1
  if (iel_src2/=iel_src) nsrcelem=2

!()()()()()()()()()()()()()
  if (have_src) then 
!()()()()()()()()()()()()()

! physical source location can only be in 2 elements
     do i=1,nsrcelem

        if (i==2) then 
           liel_src=iel_src2
           lipol_src=ipol_src2
           ljpol_src=jpol_src2
        endif

!    ~~~~~~~~~~~~~~~~~~~~~
        if (oldway) then
!    ~~~~~~~~~~~~~~~~~~~~~

           do ipol = 0,npol
              do jpol = 0,npol

                 ws(:,:,:) = zero 
                 ws(ipol,jpol,liel_src) = one
                 call dsdf_elem_solid(dsws(:,:,liel_src),ws(:,:,liel_src),&
                                      liel_src)
                 call dzdf_elem_solid(dzwz(:,:,liel_src),ws(:,:,liel_src),&
                                      liel_src)

                 poletype:  select case (src_type(1))

!    monopole
                 case ('monopole') poletype
                    select case (src_type(2))

                    case ('explosion')
                       if (ipol==0 .and. jpol==0  .and. lpr) &
                            write(6,*)'  ',procstrg, &
                           'computing source s- and z-components for explosion'

                       source_term(ipol,jpol,liel_src,1) = &
                            two*dsws(lipol_src,ljpol_src,liel_src)
                       source_term(ipol,jpol,liel_src,3) = &
                            dzwz(lipol_src,ljpol_src,liel_src)
!                  if (i==2) f(:,:,:,3)
                    case ('mxx_p_myy' ) 
                       if (ipol==0 .and. jpol==0 .and. lpr)  &
                            write(6,*)'  ',procstrg, &
                            'computing source s-component for Mxx+Myy'
                       source_term(ipol,jpol,liel_src,1) = &
!                            two*dsws(lipol_src,ljpol_src,liel_src)
                             dsws(lipol_src,ljpol_src,liel_src)

                    case ('mzz')
                       if (ipol==0 .and. jpol==0 .and. lpr)  &
                            write(6,*)'  ',procstrg, &
                            'computing source field z-component for Mzz'
                       source_term(ipol,jpol,liel_src,3) = &
                            dzwz(lipol_src,ljpol_src,liel_src)

                    case default
                       write(6,*)procstrg,&
                            'PROBLEM: Didn"t compute any source: '
                       write(6,*)procstrg,&
                            'Monopole source doesn"t exist for ', &
                            src_type(2); call flush(6); stop
                    end select

!    dipole
                 case ('dipole') poletype
                    select case(src_type(2))

                    case ('mxz','myz')
                       if (ipol==0 .and. jpol==0 .and. lpr)  &
                            write(6,*) &
                            '  computing source + and z-components for Mxz'
                       source_term(ipol,jpol,liel_src,1) =  &
                            dzwz(lipol_src,ljpol_src,liel_src)
                       source_term(ipol,jpol,liel_src,3) =  &
                            dsws(lipol_src,ljpol_src,liel_src)

                    case default
                       write(6,*)procstrg,'PROBLEM: Didn"t compute any source!'
                       write(6,*)procstrg,'Dipole source doesn"t exist for ', &
                            src_type(2); call flush(6); stop
                    end select

!    quadrupole
                 case ('quadpole') poletype

                    select case (src_type(2))

                    case ('mxy','mxx_m_myy') 
                       if (ipol==0 .and. jpol==0 .and. lpr)  &
                            write(6,*) &
                            '  computing source s- and phi-components for Mxy'
                       source_term(ipol,jpol,liel_src,1) = &
                            dsws(lipol_src,ljpol_src,liel_src) 
                       source_term(ipol,jpol,liel_src,2) = &
                            ws_over_s(lipol_src,ljpol_src,liel_src) 
                    case default
                       write(6,*)procstrg,"PROBLEM: Didn't compute any source!"
                       write(6,*)procstrg,"Quadrupole doesn't exist for",&
                            src_type(2); call flush(6); stop

                    end select
                 end select poletype

              end do !jpol
           end do ! ipol

     !~~~~~~~~~~~~~~~~~~~~~
        else ! new way
     !~~~~~~~~~~~~~~~~~~~~~
           if (eltype(ielsolid(iel_src))/='curved') then 
              write(6,*)' '
              write(6,*)'SOURCE IS IN (partly linear) ELEMENT,', &
                   'NOT DEFINED AT THIS POINT...'
              write(6,*)'PROBLEM: mapping derivatives at axis only analytical.'
              call compute_coordinates(s,z,r,theta,ielsolid(iel_src), &
                   lipol_src,ljpol_src)
              write(6,*)'SOURCE LOCATION iel,type,jpol,r:', &
                   iel_src,eltype(ielsolid(iel_src)),ljpol_src,r 
              call flush(6)
              stop
           endif

           ds=zero
           dz=zero

           call compute_coordinates(s,z,r1,theta,ielsolid(iel_src),0,0)
           call compute_coordinates(s,z,r2,theta,ielsolid(iel_src),0,npol)
           call compute_coordinates(s,z,r,theta,ielsolid(iel_src),npol,jpol_src)

           write(69,*)'  THETA (rad),Z (m):',theta,z
           write(69,*)'  R1 (m),R2 (m)',r1,r2

           do ipol=0,npol
              ds(ipol)=shp_deri_k(ipol,0,2,1)*two/(theta*z)
           enddo

           do jpol=0,npol
              dz(jpol)=shp_deri_k(jpol,jpol_src,2,2)*two/(r2-r1)
           enddo

           do ipol=0,npol
              select case (src_type(2))

              case('mxx_p_myy')
                 source_term(ipol,ljpol_src,liel_src,1)=two*ds(ipol)

              case('mzz')
                 source_term(0,ipol,liel_src,3)=dz(ipol)

              case('explosion')
                 source_term(ipol,ljpol_src,liel_src,1)=two*ds(ipol)
                 source_term(0,ipol,liel_src,3)=dz(ipol)

              case('mxz')
                 source_term(0,ipol,liel_src,1)=dz(ipol)
                 source_term(ipol,ljpol_src,liel_src,3)=ds(ipol)

              case('myz')
                 source_term(0,ipol,liel_src,1)=dz(ipol)
                 source_term(ipol,ljpol_src,liel_src,3)=ds(ipol)

              case('mxx_m_myy')
                 source_term(ipol,ljpol_src,liel_src,1)=ds(ipol)
                 source_term(ipol,ljpol_src,liel_src,2)=ds(ipol)

              case('mxy')
                 source_term(ipol,ljpol_src,liel_src,1)=ds(ipol)
                 source_term(ipol,ljpol_src,liel_src,2)=ds(ipol)

              case default
                 write(6,*)'PROBLEM: Don"t know any moment tensor component ',&
                      src_type(2); call flush(6); stop

              end select
           enddo
     !~~~~~~~~~~~~~~~~~~~~~
        endif
     !~~~~~~~~~~~~~~~~~~~~~

     enddo ! multiple source elements

! If spread over two elements (i.e., if point source coincides 
! with element edge/corner), need to divide by two
     source_term = source_term/real(nsrcelem)

     write(69,*)'source term minmax:',minval(source_term),maxval(source_term)

!()()()()()()()()()()()()()
  endif ! have_src
!()()()()()()()()()()()()()

! assembly
  write(69,*)'  ',procstrg,'assembling the source term....'
  call comm2d(source_term,nel_solid,3,'solid') 

! cut out round-off errors
  do ielem=1,nel_solid
     do ipol=0,npol
        do jpol=0,npol
           if (abs(source_term(ipol,jpol,ielem,1))< smallval) &
                source_term(ipol,jpol,ielem,1)=zero
           if (abs(source_term(ipol,jpol,ielem,2))< smallval) &
                source_term(ipol,jpol,ielem,2)=zero
           if (abs(source_term(ipol,jpol,ielem,3))< smallval) &
                source_term(ipol,jpol,ielem,3)=zero
        enddo
     enddo
  enddo

!()()()()()()()()()()()()()
  if (have_src) then
!()()()()()()()()()()()()()

     if (maxval(abs(source_term))==zero) then
        write(6,*)procstrg,'PROBLEM: No source generated!'
        write(6,*)procstrg,'Bye from define_mono_moment';call flush(6)
        stop
     endif

! mask source
     select case (src_type(1))
     case ('monopole')
        call apply_axis_mask_onecomp(source_term,nel_solid,ax_el_solid,&
                                     naxel_solid)
     case ('dipole') 
        call apply_axis_mask_twocomp(source_term,nel_solid,ax_el_solid, &
                                     naxel_solid)
     case ('quadpole') 
        call apply_axis_mask_threecomp(source_term,nel_solid,ax_el_solid, &
                                       naxel_solid)
     end select
     write(6,*)'  ...masked the source'

! write out the source element only
     fmt1 = "(K(1pe12.3))"
     write(fmt1(2:2),'(i1.1)') npol+1

     write(69,*)
     write(69,*)'  *^*^*^*^*^*^* The moment-tensor source term *^*^*^*^*^**^*^'

     liel_src=iel_src
     lipol_src=ipol_src
     ljpol_src=jpol_src

     do i =1,nsrcelem
        if (i==2) then 
           liel_src=iel_src2
           lipol_src=ipol_src2
           ljpol_src=jpol_src2
        endif

        write(69,*)'iel,jpol,r:',liel_src,ljpol_src, &
             rcoord(lipol_src,ljpol_src,ielsolid(liel_src))/1.d3
        write(69,*)'North| s-dir -->'
        if (src_type(1)=='dipole') then
           write(69,*)'  ',src_type(2),'+ component'
        else
           write(69,*)'  ',src_type(2),'s component'   
        endif
        do jpol=npol,0,-1
           write(69,fmt1)(source_term(ipol,jpol,liel_src,1),ipol=0,npol)
        enddo
        write(69,*)

        if (src_type(1)=='dipole') then
           write(69,*)src_type(2),'- component'
        else
           write(69,*)src_type(2),'phi component'   
        endif
        do jpol=npol,0,-1
           write(69,fmt1)(source_term(ipol,jpol,liel_src,2),ipol=0,npol)
        enddo
        write(69,*)

        write(69,*)src_type(2),'z component'
        do jpol=npol,0,-1
           write(69,fmt1)(source_term(ipol,jpol,liel_src,3),ipol=0,npol)
        enddo
        write(69,*)
        write(69,*)
     enddo

!()()()()()()()()()()()()()
  endif ! have_src
!()()()()()()()()()()()()()

  deallocate(ws,dsws)
  deallocate(ws_over_s,dzwz)
  deallocate(ds,dz)

end subroutine define_moment_tensor
!=============================================================================

!@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

!========================
end module source
!========================
