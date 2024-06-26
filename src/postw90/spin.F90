!-*- mode: F90 -*-!
!------------------------------------------------------------!
! This file is distributed as part of the Wannier90 code and !
! under the terms of the GNU General Public License. See the !
! file `LICENSE' in the root directory of the Wannier90      !
! distribution, or http://www.gnu.org/copyleft/gpl.txt       !
!                                                            !
! The webpage of the Wannier90 code is www.wannier.org       !
!                                                            !
! The Wannier90 code is hosted on GitHub:                    !
!                                                            !
! https://github.com/wannier-developers/wannier90            !
!------------------------------------------------------------!
!                                                            !
!  w90_spin: spin operations                                 !
!                                                            !
!------------------------------------------------------------!

module w90_spin

  !! Module to compute spin

  use w90_constants, only: dp
  use w90_error, only: w90_error_type, set_error_alloc, set_error_dealloc, set_error_fatal, &
    set_error_input, set_error_fatal, set_error_file

  implicit none

  private

  public :: spin_get_moment
  public :: spin_get_nk
  public :: spin_get_S

contains

  !================================================!
  !                   PUBLIC PROCEDURES
  !================================================!

  subroutine spin_get_moment(dis_manifold, fermi_energy_list, kpoint_dist, kpt_latt, &
                             pw90_oper_read, pw90_spin, ws_region, print_output, wannier_data, &
                             ws_distance, wigner_seitz, HH_R, SS_R, u_matrix, v_matrix, eigval, &
                             real_lattice, scissors_shift, mp_grid, num_wann, num_bands, num_kpts, &
                             num_valence_bands, effective_model, have_disentangled, &
                             wanint_kpoint_file, seedname, stdout, timer, error, comm)
    !================================================!
    !
    !! Computes the spin magnetic moment by Wannier interpolation
    !
    !================================================!

    use w90_constants, only: dp, pi
    use w90_comms, only: comms_reduce, w90_comm_type, mpirank, mpisize
    use w90_postw90_types, only: pw90_spin_mod_type, pw90_oper_read_type, wigner_seitz_type, &
      kpoint_dist_type
    use w90_types, only: print_output_type, wannier_data_type, &
      dis_manifold_type, ws_region_type, ws_distance_type, timer_list_type
    use w90_get_oper, only: get_HH_R, get_SS_R

    implicit none

    ! arguments
    type(dis_manifold_type), intent(in) :: dis_manifold
    type(kpoint_dist_type), intent(in) :: kpoint_dist
    type(pw90_oper_read_type), intent(in) :: pw90_oper_read
    type(pw90_spin_mod_type), intent(in) :: pw90_spin
    type(print_output_type), intent(in) :: print_output
    type(ws_region_type), intent(in) :: ws_region
    type(w90_comm_type), intent(in) :: comm
    type(wannier_data_type), intent(in) :: wannier_data
    type(wigner_seitz_type), intent(inout) :: wigner_seitz
    type(ws_distance_type), intent(inout) :: ws_distance
    type(timer_list_type), intent(inout) :: timer
    type(w90_error_type), allocatable, intent(out) :: error

    complex(kind=dp), allocatable, intent(inout) :: HH_R(:, :, :) !  <0n|r|Rm>
    complex(kind=dp), allocatable, intent(inout) :: SS_R(:, :, :, :) ! <0n|sigma_x,y,z|Rm>
    complex(kind=dp), intent(in) :: u_matrix(:, :, :), v_matrix(:, :, :)

    real(kind=dp), intent(in) :: eigval(:, :)
    real(kind=dp), intent(in) :: real_lattice(3, 3)
    real(kind=dp), intent(in) :: scissors_shift
    real(kind=dp), allocatable, intent(in) :: fermi_energy_list(:)
    real(kind=dp), intent(in) :: kpt_latt(:, :)

    integer, intent(in) :: mp_grid(3)
    integer, intent(in) :: num_wann, num_bands, num_kpts, num_valence_bands
    integer, intent(in) :: stdout

    logical, intent(in) :: wanint_kpoint_file

    character(len=50), intent(in)  :: seedname
    logical, intent(in) :: have_disentangled
    logical, intent(in) :: effective_model

    ! local variables
    integer       :: loop_x, loop_y, loop_z, loop_tot
    integer       :: fermi_n
    real(kind=dp) :: kweight, kpt(3), spn_k(3), spn_all(3), &
                     spn_mom(3), magnitude, theta, phi, conv

    integer :: my_node_id, num_nodes

    my_node_id = mpirank(comm)
    num_nodes = mpisize(comm)
    fermi_n = 0
    if (allocated(fermi_energy_list)) fermi_n = size(fermi_energy_list)
    if (fermi_n > 1) then
      call set_error_input(error, 'Routine spin_get_moment requires nfermi=1', comm)
      return
    endif

    call get_HH_R(dis_manifold, kpt_latt, print_output, wigner_seitz, HH_R, u_matrix, v_matrix, &
                  eigval, real_lattice, scissors_shift, num_bands, num_kpts, num_wann, &
                  num_valence_bands, effective_model, have_disentangled, seedname, stdout, timer, &
                  error, comm)
    if (allocated(error)) return

    call get_SS_R(dis_manifold, kpt_latt, print_output, pw90_oper_read, SS_R, v_matrix, eigval, &
                  wigner_seitz%irvec, wigner_seitz%nrpts, num_bands, num_kpts, num_wann, &
                  have_disentangled, seedname, stdout, timer, error, comm)
    if (allocated(error)) return

    if (print_output%iprint > 0) then
      write (stdout, '(/,/,1x,a)') '------------'
      write (stdout, '(1x,a)') 'Calculating:'
      write (stdout, '(1x,a)') '------------'
      write (stdout, '(/,3x,a)') '* Spin magnetic moment'
    end if

    spn_all = 0.0_dp
    if (wanint_kpoint_file) then

      if (print_output%iprint > 0) then
        write (stdout, '(/,1x,a)') 'Sampling the irreducible BZ only'
        write (stdout, '(5x,a)') &
          'WARNING: - IBZ implementation is currently limited to simple cases:'
        write (stdout, '(5x,a)') &
          '               Check results against a full BZ calculation!'
      end if

      ! Loop over k-points on the irreducible wedge of the Brillouin zone,
      ! read from file 'kpoint.dat'

      do loop_tot = 1, kpoint_dist%num_int_kpts_on_node(my_node_id)
        kpt(:) = kpoint_dist%int_kpts(:, loop_tot)
        kweight = kpoint_dist%weight(loop_tot)
        call spin_get_moment_k(kpt, fermi_energy_list(1), spn_k, num_wann, ws_region, &
                               wannier_data, real_lattice, mp_grid, ws_distance, HH_R, SS_R, &
                               wigner_seitz, error, comm)
        if (allocated(error)) return

        spn_all = spn_all + spn_k*kweight
      end do

    else

      if (print_output%iprint > 0) &
        write (stdout, '(/,1x,a)') 'Sampling the full BZ (not using symmetry)'
      kweight = 1.0_dp/real(PRODUCT(pw90_spin%kmesh%mesh), kind=dp)
      do loop_tot = my_node_id, PRODUCT(pw90_spin%kmesh%mesh) - 1, num_nodes
        loop_x = loop_tot/(pw90_spin%kmesh%mesh(2)*pw90_spin%kmesh%mesh(3))
        loop_y = (loop_tot - loop_x*(pw90_spin%kmesh%mesh(2)*pw90_spin%kmesh%mesh(3)))/pw90_spin%kmesh%mesh(3)
        loop_z = loop_tot - loop_x*(pw90_spin%kmesh%mesh(2)*pw90_spin%kmesh%mesh(3)) &
                 - loop_y*pw90_spin%kmesh%mesh(3)
        kpt(1) = (real(loop_x, dp)/real(pw90_spin%kmesh%mesh(1), dp))
        kpt(2) = (real(loop_y, dp)/real(pw90_spin%kmesh%mesh(2), dp))
        kpt(3) = (real(loop_z, dp)/real(pw90_spin%kmesh%mesh(3), dp))
        call spin_get_moment_k(kpt, fermi_energy_list(1), spn_k, num_wann, ws_region, &
                               wannier_data, real_lattice, mp_grid, ws_distance, HH_R, SS_R, &
                               wigner_seitz, error, comm)
        if (allocated(error)) return

        spn_all = spn_all + spn_k*kweight
      end do

    end if

    ! Collect contributions from all nodes

    call comms_reduce(spn_all(1), 3, 'SUM', error, comm)
    if (allocated(error)) return

    ! No factor of g=2 because the spin variable spans [-1,1], not
    ! [-1/2,1/2] (i.e., it is really the Pauli matrix sigma, not S)

    spn_mom(1:3) = -spn_all(1:3)

    if (print_output%iprint > 0) then
      write (stdout, '(/,1x,a)') 'Spin magnetic moment (Bohr magn./cell)'
      write (stdout, '(1x,a,/)') '===================='
      write (stdout, '(1x,a18,f11.6)') 'x component:', spn_mom(1)
      write (stdout, '(1x,a18,f11.6)') 'y component:', spn_mom(2)
      write (stdout, '(1x,a18,f11.6)') 'z component:', spn_mom(3)

      ! Polar and azimuthal angles of the magnetization (defined as in pwscf)

      conv = 180.0_dp/pi
      magnitude = sqrt(spn_mom(1)**2 + spn_mom(2)**2 + spn_mom(3)**2)
      theta = acos(spn_mom(3)/magnitude)*conv
      phi = atan(spn_mom(2)/spn_mom(1))*conv
      write (stdout, '(/,1x,a18,f11.6)') 'Polar theta (deg):', theta
      write (stdout, '(1x,a18,f11.6)') 'Azim. phi (deg):', phi
    end if

  end subroutine spin_get_moment

  !================================================!
  subroutine spin_get_nk(ws_region, pw90_spin, wannier_data, ws_distance, wigner_seitz, HH_R, &
                         SS_R, kpt, real_lattice, spn_nk, mp_grid, num_wann, error, comm)
    !================================================!
    !
    !! Computes <psi_{mk}^(H)|S.n|psi_{mk}^(H)> (m=1,...,num_wann)
    !! where S.n = n_x.S_x + n_y.S_y + n_z.Z_z
    !!
    !! S_i are the Pauli matrices and n=(n_x,n_y,n_z) is the unit
    !! vector along the chosen spin quantization axis
    !
    !================================================ !

    use w90_constants, only: dp, pi
    use w90_utility, only: utility_diagonalize, utility_rotate_diag
    use w90_types, only: print_output_type, wannier_data_type, ws_region_type, &
      ws_distance_type
    use w90_postw90_types, only: pw90_spin_mod_type, wigner_seitz_type
    use w90_postw90_common, only: pw90common_fourier_R_to_k
    use w90_comms, only: w90_comm_type

    ! arguments
    type(pw90_spin_mod_type), intent(in) :: pw90_spin
    type(ws_region_type), intent(in) :: ws_region
    type(wannier_data_type), intent(in) :: wannier_data
    type(wigner_seitz_type), intent(in) :: wigner_seitz
    type(ws_distance_type), intent(inout) :: ws_distance
    type(w90_error_type), allocatable, intent(out) :: error
    type(w90_comm_type), intent(in) :: comm

    integer, intent(in) :: num_wann
    integer, intent(in) :: mp_grid(3)

    real(kind=dp), intent(in)  :: kpt(3)
    real(kind=dp), intent(out) :: spn_nk(num_wann)
    real(kind=dp), intent(in) :: real_lattice(3, 3)

    complex(kind=dp), allocatable, intent(inout) :: HH_R(:, :, :) !  <0n|r|Rm>
    complex(kind=dp), allocatable, intent(inout) :: SS_R(:, :, :, :) ! <0n|sigma_x,y,z|Rm>

    ! local variables
    ! Physics

    complex(kind=dp), allocatable :: HH(:, :)
    complex(kind=dp), allocatable :: UU(:, :)
    complex(kind=dp), allocatable :: SS(:, :, :), SS_n(:, :)

    ! Misc/Dummy

    integer          :: is
    real(kind=dp)    :: eig(num_wann), alpha(3), conv

    allocate (HH(num_wann, num_wann))
    allocate (UU(num_wann, num_wann))
    allocate (SS(num_wann, num_wann, 3))
    allocate (SS_n(num_wann, num_wann))

    call pw90common_fourier_R_to_k(ws_region, wannier_data, ws_distance, wigner_seitz, HH, HH_R, &
                                   kpt, real_lattice, mp_grid, 0, num_wann, error, comm)
    if (allocated(error)) return
    call utility_diagonalize(HH, num_wann, eig, UU, error, comm)
    if (allocated(error)) return

    do is = 1, 3
      call pw90common_fourier_R_to_k(ws_region, wannier_data, ws_distance, wigner_seitz, &
                                     SS(:, :, is), SS_R(:, :, :, is), kpt, real_lattice, mp_grid, &
                                     0, num_wann, error, comm)
      if (allocated(error)) return
    enddo

    ! Unit vector along the magnetization direction

    conv = 180.0_dp/pi
    alpha(1) = sin(pw90_spin%axis_polar/conv)*cos(pw90_spin%axis_azimuth/conv)
    alpha(2) = sin(pw90_spin%axis_polar/conv)*sin(pw90_spin%axis_azimuth/conv)
    alpha(3) = cos(pw90_spin%axis_polar/conv)

    ! Vector of spin matrices projected along the quantization axis

    SS_n(:, :) = alpha(1)*SS(:, :, 1) + alpha(2)*SS(:, :, 2) + alpha(3)*SS(:, :, 3)

    spn_nk(:) = real(utility_rotate_diag(SS_n, UU, num_wann), dp)

  end subroutine spin_get_nk

  !================================================!
  !                   PRIVATE PROCEDURES
  !================================================!

  subroutine spin_get_moment_k(kpt, ef, spn_k, num_wann, ws_region, wannier_data, real_lattice, &
                               mp_grid, ws_distance, HH_R, SS_R, wigner_seitz, error, comm)
    !================================================!
    !! Computes the spin magnetic moment by Wannier interpolation
    !! at the specified k-point
    !================================================!

    use w90_constants, only: dp, cmplx_i
    use w90_utility, only: utility_diagonalize, utility_rotate_diag
    use w90_types, only: print_output_type, wannier_data_type, ws_region_type, &
      ws_distance_type
    use w90_postw90_common, only: pw90common_fourier_R_to_k, pw90common_get_occ
    use w90_postw90_types, only: wigner_seitz_type
    use w90_comms, only: w90_comm_type

    ! arguments
    type(ws_region_type), intent(in) :: ws_region
    type(wannier_data_type), intent(in) :: wannier_data
    type(wigner_seitz_type), intent(in) :: wigner_seitz
    type(ws_distance_type), intent(inout) :: ws_distance
    type(w90_error_type), allocatable, intent(out) :: error
    type(w90_comm_type), intent(in) :: comm

    integer, intent(in) :: mp_grid(3)
    integer, intent(in) :: num_wann

    real(kind=dp), intent(in) :: ef
    real(kind=dp), intent(in) :: kpt(3)
    real(kind=dp), intent(in) :: real_lattice(3, 3)
    real(kind=dp), intent(out) :: spn_k(3)

    complex(kind=dp), allocatable, intent(inout) :: HH_R(:, :, :) !  <0n|r|Rm>
    complex(kind=dp), allocatable, intent(inout) :: SS_R(:, :, :, :) ! <0n|sigma_x,y,z|Rm>

    ! local variables
    ! Physics

    complex(kind=dp), allocatable :: HH(:, :)
    complex(kind=dp), allocatable :: SS(:, :, :)
    complex(kind=dp), allocatable :: UU(:, :)
    real(kind=dp)                 :: spn_nk(num_wann, 3)

    ! Misc/Dummy

    integer          :: i, is
    real(kind=dp)    :: eig(num_wann), occ(num_wann)

    allocate (HH(num_wann, num_wann))
    allocate (UU(num_wann, num_wann))
    allocate (SS(num_wann, num_wann, 3))

    call pw90common_fourier_R_to_k(ws_region, wannier_data, ws_distance, wigner_seitz, HH, HH_R, &
                                   kpt, real_lattice, mp_grid, 0, num_wann, error, comm)
    if (allocated(error)) return

    call utility_diagonalize(HH, num_wann, eig, UU, error, comm)
    if (allocated(error)) return

    call pw90common_get_occ(ef, eig, occ, num_wann)

    spn_k(1:3) = 0.0_dp
    do is = 1, 3
      call pw90common_fourier_R_to_k(ws_region, wannier_data, ws_distance, wigner_seitz, &
                                     SS(:, :, is), SS_R(:, :, :, is), kpt, real_lattice, mp_grid, &
                                     0, num_wann, error, comm)
      if (allocated(error)) return

      spn_nk(:, is) = aimag(cmplx_i*utility_rotate_diag(SS(:, :, is), UU, num_wann))
      do i = 1, num_wann
        spn_k(is) = spn_k(is) + occ(i)*spn_nk(i, is)
      end do
    enddo

  end subroutine spin_get_moment_k

  !================================================!
  subroutine spin_get_S(kpt, S, num_wann, ws_region, wannier_data, real_lattice, mp_grid, &
                        ws_distance, HH_R, SS_R, wigner_seitz, error, comm)
    !================================================!
    !
    ! Computes <psi_{nk}^(H)|S|psi_{nk}^(H)> (n=1,...,num_wann)
    ! where S = (S_x,S_y,S_z) is the vector of Pauli matrices
    !
    !================================================ !

    use w90_constants, only: dp
    use w90_utility, only: utility_diagonalize, utility_rotate_diag
    use w90_types, only: print_output_type, wannier_data_type, ws_region_type, &
      ws_distance_type
    use w90_postw90_common, only: pw90common_fourier_R_to_k
    use w90_postw90_types, only: wigner_seitz_type
    use w90_comms, only: w90_comm_type

    ! arguments
    type(ws_region_type), intent(in) :: ws_region
    type(wannier_data_type), intent(in) :: wannier_data
    type(wigner_seitz_type), intent(in) :: wigner_seitz
    type(ws_distance_type), intent(inout) :: ws_distance
    type(w90_error_type), allocatable, intent(out) :: error
    type(w90_comm_type), intent(in) :: comm

    integer, intent(in) :: mp_grid(3)
    integer, intent(in) :: num_wann

    real(kind=dp), intent(in)  :: kpt(3)
    real(kind=dp), intent(in) :: real_lattice(3, 3)
    real(kind=dp), intent(out) :: S(num_wann, 3)

    complex(kind=dp), allocatable, intent(inout) :: HH_R(:, :, :) !  <0n|r|Rm>
    complex(kind=dp), allocatable, intent(inout) :: SS_R(:, :, :, :) ! <0n|sigma_x,y,z|Rm>

    ! local variables
    ! Physics
    complex(kind=dp), allocatable :: HH(:, :)
    complex(kind=dp), allocatable :: UU(:, :)
    complex(kind=dp), allocatable :: SS(:, :, :)
    real(kind=dp)                 :: eig(num_wann)

    ! Misc/Dummy
    integer :: i

    allocate (HH(num_wann, num_wann))
    allocate (UU(num_wann, num_wann))
    allocate (SS(num_wann, num_wann, 3))

    call pw90common_fourier_R_to_k(ws_region, wannier_data, ws_distance, wigner_seitz, HH, HH_R, &
                                   kpt, real_lattice, mp_grid, 0, num_wann, error, comm)
    if (allocated(error)) return

    call utility_diagonalize(HH, num_wann, eig, UU, error, comm)
    if (allocated(error)) return

    do i = 1, 3
      call pw90common_fourier_R_to_k(ws_region, wannier_data, ws_distance, wigner_seitz, &
                                     SS(:, :, i), SS_R(:, :, :, i), kpt, real_lattice, mp_grid, &
                                     0, num_wann, error, comm)
      if (allocated(error)) return

      S(:, i) = real(utility_rotate_diag(SS(:, :, i), UU, num_wann), dp)
    enddo

  end subroutine spin_get_S

end module w90_spin
