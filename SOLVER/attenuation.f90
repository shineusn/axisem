module attenuation
  use global_parameters,    only: realkind, third
  implicit none
  include 'mesh_params.h'

  private
  public :: prepare_attenuation
  public :: n_sls_attenuation
  public :: dump_memory_vars
  public :: time_step_memvars

  double precision, allocatable   :: y_j_attenuation(:)
  double precision, allocatable   :: w_j_attenuation(:), exp_w_j_deltat(:)
  double precision, allocatable   :: ts_fac_t(:), ts_fac_tm1(:)
  integer                         :: n_sls_attenuation
  logical                         :: do_corr_lowq, dump_memory_vars = .false.
  real(kind=realkind)             :: src_dev_tm1_glob(0:npol,0:npol,6,nel_solid)  
  real(kind=realkind)             :: src_tr_tm1_glob(0:npol,0:npol,nel_solid)  

contains

!-----------------------------------------------------------------------------------------
subroutine time_step_memvars(memvar, disp)
  !
  ! analytical time integration of memory variables (linear interpolation for
  ! the strain)
  ! MvD, attenutation notes, p 13.2
  !
  use data_time,            only: deltat
  use data_matr,            only: Q_mu, Q_kappa
  !use data_matr,            only: mu_r, kappa_r
  use data_matr,            only: delta_mu, delta_kappa
  use data_mesh,            only: axis_solid
  include 'mesh_params.h'

  real(kind=realkind), intent(inout)    :: memvar(0:npol,0:npol,6,n_sls_attenuation,nel_solid)
  real(kind=realkind), intent(in)       :: disp(0:npol,0:npol,nel_solid,3)
  
  integer               :: iel, j, ipol, jpol
  double precision      :: yp_j_mu(n_sls_attenuation)
  double precision      :: yp_j_kappa(n_sls_attenuation)
  double precision      :: a_j_mu(n_sls_attenuation)
  double precision      :: a_j_kappa(n_sls_attenuation)
  real(kind=realkind)   :: grad_t(0:npol,0:npol,nel_solid,6)
  real(kind=realkind)   :: trace_grad_t(0:npol,0:npol)
  real(kind=realkind)   :: trace_grad_tm1(0:npol,0:npol)
  real(kind=realkind)   :: src_tr_t(0:npol,0:npol)
  real(kind=realkind)   :: src_tr_tm1(0:npol,0:npol)
  real(kind=realkind)   :: src_dev_t(0:npol,0:npol,6)
  real(kind=realkind)   :: src_dev_tm1(0:npol,0:npol,6)
  
  real(kind=realkind)   :: src_tr_buf(0:npol,0:npol)
  real(kind=realkind)   :: src_dev_buf(0:npol,0:npol,6)
  
  real(kind=realkind)   :: Q_mu_last, Q_kappa_last

  Q_mu_last = -1
  Q_kappa_last = -1

  ! compute global strain of current time step
  call compute_strain_att(disp, grad_t)

  do iel=1, nel_solid
     ! compute local coefficients y_j for kappa and mu (only if different from
     ! previous element)
     if (Q_mu(iel) /= Q_mu_last) then
        Q_mu_last = Q_mu(iel)
        if (do_corr_lowq) then
           call fast_correct(y_j_attenuation / Q_mu(iel), yp_j_mu)
        else
           yp_j_mu = y_j_attenuation / Q_mu(iel)
        endif
        a_j_mu = yp_j_mu / sum(yp_j_mu)
     endif

     if (Q_kappa(iel) /= Q_kappa_last) then
        Q_kappa_last = Q_kappa(iel)
        if (do_corr_lowq) then
           call fast_correct(y_j_attenuation / Q_kappa(iel), yp_j_kappa)
        else
           yp_j_kappa = y_j_attenuation / Q_kappa(iel)
        endif
        a_j_kappa = yp_j_mu / sum(yp_j_kappa)
     endif

     trace_grad_t(:,:) = sum(grad_t(:,:,iel,1:3), dim=3)

     ! analytical time stepping, monopole/isotropic hardcoded

     ! compute new source terms (excluding the weighting)
     src_tr_t(:,:) = delta_kappa(:,:,iel) * trace_grad_t(:,:)
     src_dev_t(:,:,1) = delta_mu(:,:,iel) * 2 * (grad_t(:,:,iel,1) - trace_grad_t(:,:) * third)
     src_dev_t(:,:,2) = delta_mu(:,:,iel) * 2 * (grad_t(:,:,iel,2) - trace_grad_t(:,:) * third)
     src_dev_t(:,:,3) = delta_mu(:,:,iel) * 2 * (grad_t(:,:,iel,3) - trace_grad_t(:,:) * third)
     src_dev_t(:,:,5) = delta_mu(:,:,iel) * grad_t(:,:,iel,5)


     ! load old source terms
     src_tr_tm1(:,:) = src_tr_tm1_glob(:,:,iel)
     src_dev_tm1(:,:,:) = src_dev_tm1_glob(:,:,:,iel)
     
     do j=1, n_sls_attenuation
        ! do the timestep
        do jpol=0, npol
           do ipol=0, npol
              src_tr_buf(ipol,jpol) = ts_fac_t(j) * a_j_kappa(j) * src_tr_t(ipol,jpol) &
                              + ts_fac_tm1(j) * a_j_kappa(j) * src_tr_tm1(ipol,jpol)

              src_dev_buf(ipol,jpol,1:3) = &
                          ts_fac_t(j) * a_j_mu(j) * src_dev_t(ipol,jpol,1:3) &
                              + ts_fac_tm1(j) * a_j_mu(j) * src_dev_tm1(ipol,jpol,1:3)
              src_dev_buf(ipol,jpol,5) = &
                          ts_fac_t(j) * a_j_mu(j) * src_dev_t(ipol,jpol,5) &
                              + ts_fac_tm1(j) * a_j_mu(j) * src_dev_tm1(ipol,jpol,5)
              
              memvar(ipol,jpol,1,j,iel) = exp_w_j_deltat(j) * memvar(ipol,jpol,1,j,iel) &
                              + src_dev_buf(ipol,jpol,1) + src_tr_buf(ipol,jpol)
              memvar(ipol,jpol,2,j,iel) = exp_w_j_deltat(j) * memvar(ipol,jpol,2,j,iel) &
                              + src_dev_buf(ipol,jpol,2) + src_tr_buf(ipol,jpol)
              memvar(ipol,jpol,3,j,iel) = exp_w_j_deltat(j) * memvar(ipol,jpol,3,j,iel) &
                              + src_dev_buf(ipol,jpol,3) + src_tr_buf(ipol,jpol)
              memvar(ipol,jpol,5,j,iel) = exp_w_j_deltat(j) * memvar(ipol,jpol,5,j,iel) &
                              + src_dev_buf(ipol,jpol,5)
           enddo
        enddo
     enddo

     ! save srcs for next iteration
     src_tr_tm1_glob(:,:,iel) = src_tr_t(:,:)
     src_dev_tm1_glob(:,:,:,iel) = src_dev_t(:,:,:)
  enddo
  
end subroutine
!-----------------------------------------------------------------------------------------

!-----------------------------------------------------------------------------------------
subroutine compute_strain_el(u, grad_u,iel)
  !
  ! compute strain in Voigt notation 
  ! (i.e. E1 = E11, E2 = E22, E3 = E33, E4 = 2E23, E5 = 2E31, E6 = 2E12)
  !  
  use data_source,              ONLY: src_type
  use pointwise_derivatives,    ONLY: axisym_gradient_solid_el
  use pointwise_derivatives,    ONLY: f_over_s_solid_el
  
  include 'mesh_params.h'
  
  real(kind=realkind), intent(in)   :: u(0:npol,0:npol,3)
  real(kind=realkind), intent(out)  :: grad_u(0:npol,0:npol,6)
  integer, intent(in)               :: iel
  
  real(kind=realkind)               :: grad_buff1(0:npol,0:npol,2)
  real(kind=realkind)               :: grad_buff2(0:npol,0:npol,2)
  
  grad_u(:,:,:) = 0
  
  ! s,z components, identical for all source types..........................
  if (src_type(1)=='dipole') then
     call axisym_gradient_solid_el(u(:,:,1) + u(:,:,2), grad_buff1, iel)
  else
     call axisym_gradient_solid_el(u(:,:,1), grad_buff1, iel) ! 1: dsus, 2: dzus
  endif 

  call axisym_gradient_solid_el(u(:,:,3), grad_buff2, iel) ! 1:dsuz, 2:dzuz
  
  grad_u(:,:,1) = grad_buff1(:,:,1)  ! dsus
  grad_u(:,:,3) = grad_buff2(:,:,2)  ! dzuz

  grad_u(:,:,5) = grad_buff1(:,:,2) + grad_buff2(:,:,1) ! dsuz + dzus (factor of 2 
                                                              ! from voigt notation)
 
  ! Components involving phi....................................................
  ! hardcode monopole for a start

  grad_u(:,:,2) = f_over_s_solid_el(u(:,:,1), iel) ! us / s

end subroutine compute_strain_el

!-----------------------------------------------------------------------------------------
subroutine compute_strain_att(u, grad_u)
  !
  ! compute strain in Voigt notation 
  ! (i.e. E1 = E11, E2 = E22, E3 = E33, E4 = 2E23, E5 = 2E31, E6 = 2E12)
  !  
  use data_source,              ONLY: src_type
  !use pointwise_derivatives,    ONLY: axisym_gradient_solid_add
  use pointwise_derivatives,    ONLY: axisym_gradient_solid
  !use pointwise_derivatives,    ONLY: axisym_dsdf_solid
  use pointwise_derivatives,    ONLY: f_over_s_solid
  
  include 'mesh_params.h'
  
  real(kind=realkind), intent(in)   :: u(0:npol,0:npol,nel_solid,3)
  real(kind=realkind), intent(out)  :: grad_u(0:npol,0:npol,nel_solid,6)
  
  real(kind=realkind)               :: grad_buff1(0:npol,0:npol,nel_solid,2)
  real(kind=realkind)               :: grad_buff2(0:npol,0:npol,nel_solid,2)
  
  grad_u(:,:,:,:) = 0
  
  ! s,z components, identical for all source types..........................
  if (src_type(1)=='dipole') then
     call axisym_gradient_solid(u(:,:,:,1) + u(:,:,:,2), grad_buff1)
  else
     call axisym_gradient_solid(u(:,:,:,1), grad_buff1) ! 1: dsus, 2: dzus
  endif

  call axisym_gradient_solid(u(:,:,:,3), grad_buff2) ! 1:dsuz, 2:dzuz
  
  grad_u(:,:,:,1) = grad_buff1(:,:,:,1)  ! dsus
  grad_u(:,:,:,3) = grad_buff2(:,:,:,2)  ! dzuz

  grad_u(:,:,:,5) = grad_buff1(:,:,:,2) + grad_buff2(:,:,:,1) ! dsuz + dzus (factor of 2 
                                                              ! from voigt notation)
 
  ! Components involving phi....................................................
  ! hardcode monopole for a start

  grad_u(:,:,:,2) = f_over_s_solid(u(:,:,:,1)) ! us / s

end subroutine compute_strain_att
!-----------------------------------------------------------------------------------------

!-----------------------------------------------------------------------------------------
subroutine prepare_attenuation(lambda, mu)
  !
  ! read 'inparam_attenuation' file and compute precomputable terms
  !
  use data_io,              only: infopath, lfinfo
  use data_proc,            only: lpr
  use data_time,            only: deltat
  use global_parameters,    only: pi
  use data_matr,            only: Q_mu, Q_kappa
  !use data_matr,            only: mu_r, kappa_r
  use data_matr,            only: delta_mu, delta_kappa
  use data_mesh_preloop,    only: ielsolid
  use get_mesh,             only: compute_coordinates_mesh
  use data_mesh,            only: axis_solid
  use data_spec,            only: eta, xi_k, wt, wt_axial_k
  use geom_transf,          only: jacobian
  use utlity,               only: scoord
  use analytic_mapping,     only: compute_partial_derivatives
  use data_source,          only: nelsrc, ielsrc
  

  include 'mesh_params.h'

  double precision, intent(inout)   :: lambda(0:npol,0:npol,1:nelem)
  double precision, intent(inout)   :: mu(0:npol,0:npol,1:nelem)

  double precision                  :: mu_w1(0:npol,0:npol)
  double precision                  :: mu_r(0:npol,0:npol)
  double precision                  :: kappa_r(0:npol,0:npol)

  double precision                  :: delta_mu_0(0:npol,0:npol)
  double precision                  :: kappa_w1(0:npol,0:npol)
  double precision                  :: delta_kappa_0(0:npol,0:npol)
  double precision                  :: mu_u(0:npol,0:npol)
  double precision                  :: kappa_u(0:npol,0:npol)
  
  double precision                  :: kappa_fac, mu_fac

  double precision                  :: f_min, f_max, w_1, w_0
  integer                           :: nfsamp, max_it, i, iel, j
  double precision                  :: Tw, Ty, d
  logical                           :: fixfreq
  double precision, allocatable     :: w_samp(:), q_fit(:), chil(:)
  double precision, allocatable     :: yp_j_mu(:)
  double precision, allocatable     :: yp_j_kappa(:)
  
  double precision                  :: local_crd_nodes(8,2)
  double precision                  :: gamma_w_l(0:npol,0:npol)
  integer                           :: inode, ipol, jpol
  double precision                  :: dsdxi, dzdxi, dsdeta, dzdeta
  double precision                  :: weights_cg(0:npol,0:npol)

  if (lpr) print *, '  ...reading inparam_attanuation...'
  open(unit=164, file='inparam_attenuation')

  read(164,*) n_sls_attenuation
  read(164,*) f_min
  read(164,*) f_max
  read(164,*) w_0
  read(164,*) do_corr_lowq
  
  read(164,*) nfsamp
  read(164,*) max_it
  read(164,*) Tw
  read(164,*) Ty
  read(164,*) d
  read(164,*) fixfreq
  read(164,*) dump_memory_vars

  close(unit=164)
  
  w_0 = w_0 * (2 * pi)
  if (lpr) print *, '       w_0 = ', w_0
  
  w_1 = dsqrt(f_min * f_max) * (2 * pi)
  if (lpr) print *, '       w_1 = ', w_1

  if (f_min > f_max) then
     print *, "ERROR: minimum frequency larger then maximum frequency"
     print *, "       in inparam_attenuation:2-3"
     stop 2
  endif

  allocate(w_samp(nfsamp))
  allocate(q_fit(nfsamp))
  allocate(chil(max_it))
  
  allocate(w_j_attenuation(1:n_sls_attenuation))
  allocate(exp_w_j_deltat(1:n_sls_attenuation))
  allocate(y_j_attenuation(1:n_sls_attenuation))
  
  allocate(yp_j_mu(1:n_sls_attenuation))
  allocate(yp_j_kappa(1:n_sls_attenuation))
  
  allocate(ts_fac_t(1:n_sls_attenuation))
  allocate(ts_fac_tm1(1:n_sls_attenuation))
  
  
  if (lpr) print *, '  ...inverting for standard linear solid parameters...'

  call invert_linear_solids(1.d0, f_min, f_max, n_sls_attenuation, nfsamp, max_it, Tw, &
                            Ty, d, fixfreq, .false., .false., 'maxwell', w_j_attenuation, &
                            y_j_attenuation, w_samp, q_fit, chil)
  if (lpr) print *, '  ...done'
  
  ! prefactors for the exact time stepping (att nodes p 13.3)
  do j=1, n_sls_attenuation
     exp_w_j_deltat(j) = dexp(-w_j_attenuation(j) * deltat)
     ts_fac_tm1(j) = ((1 - exp_w_j_deltat(j)) / (w_j_attenuation(j) * deltat) &
                      - exp_w_j_deltat(j))
     ts_fac_t(j) = ((exp_w_j_deltat(j) - 1) / (w_j_attenuation(j) * deltat) + 1)
  enddo

  if (lpr) then
      print *, '  ...log-l2 misfit    : ', chil(max_it)
      print *, '  ...frequencies      : ', w_j_attenuation / (2. * pi)
      print *, '  ...coefficients y_j : ', y_j_attenuation
      print *, '  ...exp-frequencies  : ', exp_w_j_deltat
      print *, '  ...ts_fac_t         : ', ts_fac_t
      print *, '  ...ts_fac_tm1       : ', ts_fac_tm1

      print *, '  ...writing fitted Q to file...'
      open(unit=165, file=infopath(1:lfinfo)//'/attenuation_q_fitted', status='new')
      write(165,*) (w_samp(i), q_fit(i), char(10), i=1,nfsamp)
      close(unit=165)
      
      print *, '  ...writing convergence of chi to file...'
      open(unit=166, file=infopath(1:lfinfo)//'/attenuation_convergence', status='new')
      write(166,*) (chil(i), char(10), i=1,max_it)
      close(unit=166)
  endif


  if (lpr) print *, '  ...calculating relaxed moduli...'

  !allocate(mu_r(0:npol,0:npol,nel_solid))
  !allocate(kappa_r(0:npol,0:npol,nel_solid))
  allocate(delta_mu(0:npol,0:npol,nel_solid))
  allocate(delta_kappa(0:npol,0:npol,nel_solid))
  
  if (lpr) open(unit=1717, file=infopath(1:lfinfo)//'/weights', status='new')

  do iel=1, nel_solid
     !weighting for coarse grained memory vars (hard coded for polynomial order 4)

     do inode = 1, 8
        call compute_coordinates_mesh(local_crd_nodes(inode,1), &
                                      local_crd_nodes(inode,2), ielsolid(iel), inode)
     end do

     if (.not. axis_solid(iel)) then ! non-axial elements

        do ipol=0, npol
           do jpol=0, npol
              gamma_w_l(ipol, jpol) = wt(ipol) * wt(jpol) &
                    * jacobian(eta(ipol), eta(jpol), local_crd_nodes, ielsolid(iel)) &
                    * scoord(ipol,jpol,ielsolid(iel))
           enddo
        enddo
     else
        do ipol=1, npol
           do jpol=0, npol
              gamma_w_l(ipol, jpol) = wt_axial_k(ipol) * wt(jpol) / (1 + xi_k(ipol)) &
                    * jacobian(xi_k(ipol), eta(jpol), local_crd_nodes, ielsolid(iel)) &
                    * scoord(ipol,jpol,ielsolid(iel))
           enddo
        enddo
        
        ! axis terms
        ipol = 0
        do jpol=0, npol
           call compute_partial_derivatives(dsdxi, dzdxi, dsdeta, dzdeta, &
                   xi_k(ipol), eta(jpol), local_crd_nodes, ielsolid(iel))
           gamma_w_l(ipol, jpol) = wt_axial_k(ipol) * wt(jpol) &
                    * jacobian(xi_k(ipol), eta(jpol), local_crd_nodes, ielsolid(iel)) &
                    * dsdxi
           !gamma_w_l(ipol, jpol) = 0
        enddo
     endif
     
     weights_cg(:,:) = 1
        
     !if (.not. axis_solid(iel)) then
        weights_cg(:,:) = 0
        !! 4 points
        weights_cg(1,1) = (   gamma_w_l(0,0) + gamma_w_l(0,1) &
                            + gamma_w_l(1,0) + gamma_w_l(1,1) &
                            + 0.5 * (  gamma_w_l(0,2) + gamma_w_l(1,2) &
                                     + gamma_w_l(2,0) + gamma_w_l(2,1)) &
                            + 0.25 * gamma_w_l(2,2) ) &
                          / gamma_w_l(1,1)
        
        weights_cg(1,3) = (   gamma_w_l(0,3) + gamma_w_l(0,4) &
                            + gamma_w_l(1,3) + gamma_w_l(1,4) &
                            + 0.5 * (  gamma_w_l(0,2) + gamma_w_l(1,2) &
                                     + gamma_w_l(2,3) + gamma_w_l(2,4)) &
                            + 0.25 * gamma_w_l(2,2) ) &
                          / gamma_w_l(1,3)
        
        weights_cg(3,1) = (   gamma_w_l(3,0) + gamma_w_l(3,1) &
                            + gamma_w_l(4,0) + gamma_w_l(4,1) &
                            + 0.5 * (  gamma_w_l(2,0) + gamma_w_l(2,1) &
                                     + gamma_w_l(3,2) + gamma_w_l(4,2)) &
                            + 0.25 * gamma_w_l(2,2) ) &
                          / gamma_w_l(3,1)
        
        weights_cg(3,3) = (   gamma_w_l(3,3) + gamma_w_l(3,4) &
                            + gamma_w_l(4,3) + gamma_w_l(4,4) &
                            + 0.5 * (  gamma_w_l(2,3) + gamma_w_l(2,4) &
                                     + gamma_w_l(3,2) + gamma_w_l(4,2)) &
                            + 0.25 * gamma_w_l(2,2) ) &
                          / gamma_w_l(3,3)
        if (lpr) write(1717,*) weights_cg(1,1), weights_cg(1,3), & 
                               weights_cg(3,1), weights_cg(3,3)

        ! 5 points
        !weights_cg(1,1) = (   gamma_w_l(0,0) + gamma_w_l(0,1) &
        !                    + gamma_w_l(1,0) + gamma_w_l(1,1) &
        !                    + 0.5 * (  gamma_w_l(0,2) + gamma_w_l(1,2) &
        !                             + gamma_w_l(2,0) + gamma_w_l(2,1)) )&
        !                  / gamma_w_l(1,1)
        !
        !weights_cg(1,3) = (   gamma_w_l(0,3) + gamma_w_l(0,4) &
        !                    + gamma_w_l(1,3) + gamma_w_l(1,4) &
        !                    + 0.5 * (  gamma_w_l(0,2) + gamma_w_l(1,2) &
        !                             + gamma_w_l(2,3) + gamma_w_l(2,4)) )&
        !                  / gamma_w_l(1,3)
        !
        !weights_cg(3,1) = (   gamma_w_l(3,0) + gamma_w_l(3,1) &
        !                    + gamma_w_l(4,0) + gamma_w_l(4,1) &
        !                    + 0.5 * (  gamma_w_l(2,0) + gamma_w_l(2,1) &
        !                             + gamma_w_l(3,2) + gamma_w_l(4,2)) )&
        !                  / gamma_w_l(3,1)
        !
        !weights_cg(3,3) = (   gamma_w_l(3,3) + gamma_w_l(3,4) &
        !                    + gamma_w_l(4,3) + gamma_w_l(4,4) &
        !                    + 0.5 * (  gamma_w_l(2,3) + gamma_w_l(2,4) &
        !                             + gamma_w_l(3,2) + gamma_w_l(4,2)) )&
        !                  / gamma_w_l(3,3)
        !weights_cg(2,2) = 1
        !if (lpr) write(1717,*) weights_cg(1,1), weights_cg(1,3), & 
        !                       weights_cg(3,1), weights_cg(3,3), weights_cg(2,2)
        
        ! 9 points
        !weights_cg(1,1) = (   gamma_w_l(0,0) + gamma_w_l(0,1) &
        !                    + gamma_w_l(1,0) + gamma_w_l(1,1) )&
        !                  / gamma_w_l(1,1)

        !weights_cg(1,2) = (   gamma_w_l(0,2) + gamma_w_l(1,2) )&
        !                  / gamma_w_l(1,2)

        !weights_cg(1,3) = (   gamma_w_l(0,3) + gamma_w_l(0,4) &
        !                    + gamma_w_l(1,3) + gamma_w_l(1,4) )&
        !                  / gamma_w_l(1,3)

        !weights_cg(2,1) = (   gamma_w_l(2,0) + gamma_w_l(2,1) )&
        !                  / gamma_w_l(2,1)

        !weights_cg(2,2) = 1

        !weights_cg(2,3) = (   gamma_w_l(2,3) + gamma_w_l(2,4) )&
        !                  / gamma_w_l(2,3)

        !weights_cg(3,1) = (   gamma_w_l(3,0) + gamma_w_l(3,1) &
        !                    + gamma_w_l(4,0) + gamma_w_l(4,1) )&
        !                  / gamma_w_l(3,1)

        !weights_cg(3,2) = (   gamma_w_l(3,2) + gamma_w_l(4,2) )&
        !                  / gamma_w_l(3,2)

        !weights_cg(3,3) = (   gamma_w_l(3,3) + gamma_w_l(3,4) &
        !                    + gamma_w_l(4,3) + gamma_w_l(4,4) )&
        !                  / gamma_w_l(3,3)
        
     !endif

     !if (axis_solid(iel)) then
     !   weights_cg(:,:) = 1

     !   Q_mu(iel) = 1e9
     !   Q_kappa(iel) = 1e9

     !   !weights_cg(0,:) = 0
     !   !weights_cg(:,1) = (gamma_w_l(:,0) + gamma_w_l(:,1) + 0.5 * gamma_w_l(:,2)) &
     !   !                        / gamma_w_l(:,1)
     !   !weights_cg(:,3) = (gamma_w_l(:,4) + gamma_w_l(:,3) + 0.5 * gamma_w_l(:,2)) &
     !   !                        / gamma_w_l(:,3)
     !   !weights_cg(1,:) = (gamma_w_l(0,:) + gamma_w_l(1,:) + 0.5 * gamma_w_l(2,:)) &
     !   !                        / gamma_w_l(1,:)
     !   !weights_cg(3,:) = (gamma_w_l(4,:) + gamma_w_l(3,:) + 0.5 * gamma_w_l(2,:)) &
     !   !                        / gamma_w_l(3,:)
     !   if (lpr) write(1717,*) weights_cg(1,:)
     !   if (lpr) write(1717,*) weights_cg(3,:)
     !endif

     
     if (do_corr_lowq) then
        call fast_correct(y_j_attenuation / Q_mu(iel), yp_j_mu)
        call fast_correct(y_j_attenuation / Q_kappa(iel), yp_j_kappa)
     else
       yp_j_mu = y_j_attenuation / Q_mu(iel)
       yp_j_kappa = y_j_attenuation / Q_kappa(iel)
     endif

     !---------------------------------------------------
     !!coarse grain version
     mu_fac = 0
     do i=1, n_sls_attenuation
        mu_fac = mu_fac + yp_j_mu(i) * w_j_attenuation(i)**2 &
                            / (w_1**2 + w_j_attenuation(i)**2)
     enddo
     mu_fac = mu_fac / sum(yp_j_mu)

     kappa_fac = 0
     do i=1, n_sls_attenuation
        kappa_fac = kappa_fac + yp_j_kappa(i) * w_j_attenuation(i)**2 &
                            / (w_1**2 + w_j_attenuation(i)**2)
     enddo
     kappa_fac = kappa_fac / sum(yp_j_kappa)

     ! compute moduli at central frequency w_1
     mu_w1(:,:) =  mu(:,:,ielsolid(iel)) * (1 + 2. / (pi * Q_mu(iel)) * log(w_1 / w_0))
     kappa_w1(:,:) =  (lambda(:,:,ielsolid(iel)) + 2.d0 / 3.d0 * mu(:,:,ielsolid(iel))) &
                         * (1 + 2. / (pi * Q_kappa(iel)) * log(w_1 / w_0))

     ! delta moduli
     delta_mu_0(:,:) = mu_w1(:,:) / (1.d0 / sum(yp_j_mu) + 1 - mu_fac)
     delta_kappa_0(:,:) = kappa_w1(:,:) / (1.d0 / sum(yp_j_kappa) + 1 - kappa_fac)
     
     ! compute unrelaxed moduli
     mu(:,:,ielsolid(iel)) = mu_w1(:,:) + weights_cg(:,:) * delta_mu_0(:,:) * mu_fac
     lambda(:,:,ielsolid(iel)) = kappa_w1(:,:) &
                                    + weights_cg(:,:) * delta_kappa_0(:,:) * kappa_fac &
                                    - 2.d0 / 3.d0 * mu(:,:,ielsolid(iel))
     
     ! weighted delta moduli
     delta_mu(:,:,iel) = weights_cg(:,:) * delta_mu_0(:,:)
     delta_kappa(:,:,iel) = weights_cg(:,:) * delta_kappa_0(:,:)
     !---------------------------------------------------


     !---------------------------------------------------
     ! old version: assuming background model is instantaneous velocities
     !mu_r(:,:,iel) =  mu(:,:,ielsolid(iel)) / (1.d0 + sum(yp_j_mu))
     !kappa_r(:,:,iel) =  (lambda(:,:,ielsolid(iel)) &
     !                       + 2.d0 / 3.d0 * mu(:,:,ielsolid(iel))) &
     !                       / (1.d0 + sum(yp_j_kappa))
     !---------------------------------------------------
     
     
     !---------------------------------------------------
     ! testing simple version: assuming background model is instantaneous velocities
     !mu_r(:,:) =  mu(:,:,ielsolid(iel)) / (1.d0 + sum(yp_j_mu))
     !kappa_r(:,:) =  (lambda(:,:,ielsolid(iel)) + 2.d0 / 3.d0 * mu(:,:,ielsolid(iel))) &
     !                       / (1.d0 + sum(yp_j_kappa))

     !delta_mu(:,:,iel) = mu(:,:,ielsolid(iel)) - mu_r(:,:)
     !delta_kappa(:,:,iel) = (lambda(:,:,ielsolid(iel)) &
     !                         + 2.d0 / 3.d0 * mu(:,:,ielsolid(iel))) - kappa_r(:,:)

     !delta_mu(:,:,iel) = delta_mu(:,:,iel) * weights_cg
     !delta_kappa(:,:,iel) = delta_kappa(:,:,iel) * weights_cg
     !---------------------------------------------------

  enddo

  if (lpr) close(unit=1717)
  
  if (lpr) print *, '  ...DONE'

end subroutine
!-----------------------------------------------------------------------------------------

!-----------------------------------------------------------------------------------------
subroutine q_linear_solid(y_j, w_j, w, exact, Qls)
    !
    ! compute Q after (Emmerich & Korn, inverse of eq 21)
    ! linearized version (exact = false) is eq 22 in E&K
    !
    double precision, intent(in)    :: y_j(:), w_j(:), w(:)
    double precision, intent(out)   :: Qls(size(w))
    integer                         :: j
    
    logical, optional, intent(in)           :: exact
    !f2py logical, optional, intent(in)     :: exact = 0 
    logical                                 :: exact_loc = .false.
    
    double precision                :: Qls_denom(size(w))
    
    if (present(exact)) exact_loc = exact
    
    Qls = 1
    if (exact_loc) then
        do j=1, size(y_j)
            Qls = Qls + y_j(j) *  w**2 / (w**2 + w_j(j)**2)
        enddo
    endif
    
    Qls_denom = 0
    do j=1, size(y_j)
        Qls_denom = Qls_denom + y_j(j) * w * w_j(j) / (w**2 + w_j(j)**2)
    enddo

    Qls = Qls / Qls_denom
end subroutine
!-----------------------------------------------------------------------------------------

!-----------------------------------------------------------------------------------------
subroutine fast_correct(y_j, yp_j)
    !
    ! computes a first order correction to the linearized coefficients:
    ! yp_j_corrected = y_j * delta_j 
    !
    ! MvD Attenuation Notes, p. 17.3 bottom
    !
    double precision, intent(in)    :: y_j(:)
    double precision, intent(out)   :: yp_j(size(y_j))
    
    double precision                :: dy_j(size(y_j))
    integer                         :: k

    dy_j(1) = 1 + .5 * y_j(1)

    do k=2, size(y_j)
        dy_j(k) = dy_j(k-1) + (dy_j(k-1) - .5) * y_j(k-1) + .5 * y_j(k)
    enddo

    yp_j = y_j * dy_j
    
end subroutine
!-----------------------------------------------------------------------------------------

!-----------------------------------------------------------------------------------------
subroutine l2_error(Q, Qls, lognorm, lse)
    !
    ! returns l2 misfit between constant Q and fitted Q using standard linear solids
    !
    double precision, intent(in)    :: Q, Qls(:)
    
    logical, optional, intent(in)   :: lognorm
    ! optional argument with default value (a bit nasty in f2py)
    !f2py logical, optional, intent(in) :: lognorm = 1
    logical :: lognorm_loc = .true.
    
    double precision, intent(out)   :: lse
    integer                         :: nfsamp, i
    
    if (present(lognorm)) lognorm_loc = lognorm

    lse = 0
    nfsamp = size(Qls)

    if (lognorm_loc) then
        !print *, 'log-l2 norm'
        do i=1, nfsamp
            lse = lse + (log(Q / Qls(i)))**2
        end do
    else
        !print *, 'standard l2 norm'
        do i=1, nfsamp
            lse = lse + (1/Q - 1/Qls(i))**2
        end do
        lse = lse * Q**2
    endif
    lse = lse / float(nfsamp)
    lse = dsqrt(lse)
end subroutine
!-----------------------------------------------------------------------------------------

!-----------------------------------------------------------------------------------------
subroutine invert_linear_solids(Q, f_min, f_max, N, nfsamp, max_it, Tw, Ty, d, &
                                 fixfreq, verbose, exact, mode, w_j, y_j, w, q_fit, chil)
    !
    ! Inverts for constant Q, minimizing the L2 error for 1/Q using a simulated annealing
    ! approach (varying peak frequencies and amplitudes).

    ! Parameters:
    ! Q:              clear
    ! f_min, fmax:    frequency band (in Hz)
    ! N:              number of standard linear solids
    ! nfsamp:         number of sampling frequencies for computation of the misfit (log
    !                   spaced in freqeuncy band)

    ! max_it:         number of iterations
    ! Tw:             starting temperature for the frequencies
    ! Ty:             starting temperature for the amplitudes
    ! d:              temperature decay
    ! fixfreq:        use log spaced peak frequencies (fixed)
    ! verbose:        clear
    ! exact:          use exact relation for Q and the coefficients (Emmerich & Korn, eq
    !                   21). If false, linearized version is used (large Q approximation, eq
    !                   22).
    ! mode:           'maxwell' (default) oder 'zener' depending on the reology
    !
    ! Returns:
    ! w_j:            relaxation frequencies, equals 1/tau_sigma in zener
    !                   formulation
    ! y_j:            coefficients of the linear solids, (Emmerich & Korn, eq 23 and 24)
    !                   if mode is set to 'zener', this array contains the
    !                   tau_epsilon as defined by Blanch et al, eq 12.
    ! w:              sampling frequencies at which Q(w) is minimized
    ! q_fit:          resulting q(w) at these frequencies
    ! chil:           error as a function of iteration to check convergence,
    !                   Note that this version uses log-l2 norm!
    !
    use data_proc,            only: lpr, mynum

    double precision, intent(in)            :: Q, f_min, f_max
    integer, intent(in)                     :: N, nfsamp, max_it

    double precision, optional, intent(in)          :: Tw, Ty, d
    !f2py double precision, optional, intent(in)    :: Tw=.1, Ty=.1, d=.99995
    double precision                                :: Tw_loc = .1, Ty_loc = .1
    double precision                                :: d_loc = .99995

    logical, optional, intent(in)           :: fixfreq, verbose, exact
    !f2py logical, optional, intent(in)     :: fixfreq = 0, verbose = 0
    !f2py logical, optional, intent(in)     :: exact = 0
    logical                                 :: fixfreq_loc = .false., verbose_loc = .false.
    logical                                 :: exact_loc = .false.
    
    character(len=7), optional, intent(in)  :: mode
    !f2py character(len=7), optional, intent(in) :: mode = 'maxwell'
    character(len=7)                        :: mode_loc = 'maxwell'

    double precision, intent(out)   :: w_j(N)
    double precision, intent(out)   :: y_j(N)
    double precision, intent(out)   :: w(nfsamp) 
    double precision, intent(out)   :: q_fit(nfsamp) 
    double precision, intent(out)   :: chil(max_it) 

    double precision                :: w_j_test(N)
    double precision                :: y_j_test(N)
    double precision                :: expo
    double precision                :: chi, chi_test

    integer             :: j, it, last_it_print

    ! set default values
    if (present(Tw)) Tw_loc = Tw
    if (present(Ty)) Ty_loc = Ty
    if (present(d)) d_loc = d

    if (present(fixfreq)) fixfreq_loc = fixfreq
    if (present(verbose)) verbose_loc = verbose
    if (present(exact)) exact_loc = exact
    
    if (present(mode)) mode_loc = mode

    if (.not. lpr) verbose_loc = .false.
    
    if ((mode_loc .ne. 'maxwell') .and. (mode_loc .ne. 'zener')) then
        print *, "ERROR: mode should be either 'maxwell' or 'zener'"
        return
    endif


    ! Set the starting test frequencies equally spaced in log frequency
    if (N > 1) then
        expo = (log10(f_max) - log10(f_min)) / (N - 1.d0)
        do j=1, N
            ! pi = 4 * atan(1)
            w_j_test(j) = datan(1.d0) * 8.d0 * 10**(log10(f_min) + (j - 1) * expo)
        end do 
    else
        w_j_test(1) = (f_max * f_min)**.5 * 8 * datan(1.d0)
    endif


    if (verbose_loc) print *, w_j_test
    
    ! Set the sampling frequencies equally spaced in log frequency
    expo = (log10(f_max) - log10(f_min)) / (nfsamp - 1.d0)
    do j=1, nfsamp
        w(j) = datan(1.d0) * 8.d0 * 10**(log10(f_min) + (j - 1) * expo)
    end do

    if (verbose_loc) print *, w
    
    ! initial weights
    y_j_test = 1.d0 / Q * 1.5
    if (verbose_loc) print *, y_j_test

    ! initial Q(omega)
    call q_linear_solid(y_j=y_j_test, w_j=w_j_test, w=w, exact=exact_loc, Qls=q_fit)
    
    if (verbose_loc) print *, q_fit
   
    ! initial chi
    call l2_error(Q=Q, Qls=q_fit, lognorm=.true., lse=chi)
    if (verbose_loc) print *, 'initital chi: ', chi

    y_j(:) = y_j_test(:)
    w_j(:) = w_j_test(:)
    
    last_it_print = -1
    do it=1, max_it
        do j=1, N
            if (.not. fixfreq_loc) &
                w_j_test(j) = w_j(j) * (1.0 + (0.5 - rand()) * Tw_loc)
            y_j_test(j) = y_j(j) * (1.0 + (0.5 - rand()) * Ty_loc)
        enddo
    
        ! compute Q with test parameters
        call q_linear_solid(y_j=y_j_test, w_j=w_j_test, w=w, exact=exact_loc, Qls=q_fit)
        
        ! compute new misfit and new temperature
        call l2_error(Q=Q, Qls=q_fit, lognorm=.true., lse=chi_test)
        Tw_loc = Tw_loc * d_loc
        Ty_loc = Ty_loc * d_loc
                                        
        ! check if the tested parameters are better
        if (chi_test < chi) then
            y_j(:) = y_j_test(:)
            w_j(:) = w_j_test(:)
            chi = chi_test

            if (verbose_loc) then
                print *, '---------------'
                print *, it, chi
                print *, w_j / (8 * tan(1.))
                print *, y_j
            endif
    
        endif
        chil(it) = chi
    enddo

    if (mode_loc .eq. 'zener') then
        ! compare Attenuation Notes, p 18.1
        ! easy to find from Blanch et al, eq. (12) and Emmerick & Korn, eq. (21)
        y_j = (y_j + 1) / w_j
    endif

end subroutine
!-----------------------------------------------------------------------------------------

end module
