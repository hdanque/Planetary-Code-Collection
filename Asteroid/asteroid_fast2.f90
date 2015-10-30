program asteroid_fast
!***********************************************************************
! Asynchronously coupled model of temperature and ice retreat on asteroids
! written by Norbert Schorghofer 2012-2015
!***********************************************************************
  use constants, only : pi, d2r, NMAX
  use body, only : nz, zfac, zmax, ecc, icedensity
  use allinterfaces
  implicit none

  integer, parameter :: NP=1    ! # of sites
  integer SPINUPN   ! # number of spin-up steps
  real(8) spinupfac 
  parameter(SPINUPN=20, spinupfac=2.)
  integer i, k, earliest, iargc, ierr
  real(8) tstart  ! (earth) years
  real(8) z(NMAX), icetime, timestep, sigma(nz,NP)
  real(8) bigstep, bssum, omega, eps, porosity(nz)
  real(8), dimension(NP) :: latitude, albedo, zdepthP
  real(8), dimension(NP) :: Tmean1, Tmean3, Tmin, Tmax
  character(4) ext
  real(8), parameter :: thIn = 15.

  ! latitudes
  if (iargc() /= 1) then
     stop 'USAGE: asteroid_fast ext'
  endif
  call getarg( 1, ext )
  open(unit=21,file='lats.'//ext,action='read',status='old',iostat=ierr)
  if (ierr /= 0) then
     print *,'File lats.'//ext,'not found'
     stop
  endif
  do k=1,NP
     read(21,*,iostat=ierr) latitude(k),albedo(k)
  enddo
  close(21)

  ! parameters that never change
  tstart = 1e6  ! Earth years
  tstart = 4.5e9  ! Earth years
  timestep = 1e5  ! Earth years

  ! set eternal grid
  call setgrid(nz,z,zmax,zfac)
  open(unit=30,file='z.'//ext,action='write',status='unknown')
  write(30,'(999(f8.5,1x))') z(1:nz)
  close(30)

  ! initial ice depth and ice content
  zdepthP(:) = 0.
  porosity(:) = 0.4d0   ! dry porosity
  forall (i=1:nz) sigma(i,:) = porosity(i)*icedensity

  ! (1) Ceres
  eps = 4.*d2r 
  omega = 0.

  print *,'RUNNING FAST ASTEROID MODEL'
  print *,'Starting at time',tstart,'years'
  print *,'Time step=',timestep,'years'
  print *,'Spinup',SPINUPN,spinupfac
  print *,'eps=',eps/d2r,'ecc=',ecc,'omega=',omega/d2r
  print *,'Number of sites=',NP
  print *,'Thermal inertia=',thIn
  print *,'Site specific parameters:'
  do k=1,NP
     if (NP>1) print *,'  Site ',k
     print *,'  Latitude (deg)',latitude(k)
     call outputskindepths(nz,z,zmax,porosity)
     print *,'  Initial ice depth=',zdepthP(k)
     print *
  enddo
  call outputmoduleparameters
  print *

  open(unit=34,file='subout.'//ext,action='write',status='unknown')
  open(unit=37,file='depths.'//ext,action='write',status='unknown')
  open(unit=36,file='icecontent.'//ext,action='write',status='unknown')

  earliest = nint(tstart/timestep)
  icetime = -earliest*timestep

  print *,'Equilibrating initial temperature'
  !icetime = -tstart
  call icelayer_asteroid(0d0,NP,thIn,z,porosity,.true., &
       &        zdepthP,sigma,Tmean1,Tmean3,Tmin,Tmax,latitude,albedo, &
       &        ecc,omega,eps,faintsun(icetime))
  do k=1,NP
     write(37,501) icetime,latitude(k),zdepthP(k), &
          &  Tmean1(k),Tmean3(k),Tmin(k),Tmax(k)
     write(36,'(f12.0,2x,f7.3,2x)',advance='no') icetime,latitude(k)
     call compactoutput(36,sigma(1:nz,k),nz)
  enddo

  icetime = - earliest*timestep
  print *,icetime
  print *,'Spin-up begins here'
  bssum=spinupfac*(spinupfac**SPINUPN-1)/(spinupfac-1.) ! sum_{j=1,n} a^j = a (a^n-1)/(a-1)
  print *,'Spin-up', SPINUPN,'steps over',timestep,'years'
  do i=1,SPINUPN
     bigstep = spinupfac**i/bssum*timestep
     icetime = icetime + bigstep
     call icelayer_asteroid(bigstep,NP,thIn,z,porosity,.false., &
          & zdepthP,sigma,Tmean1,Tmean3,Tmin,Tmax,latitude,albedo, &
          & ecc,omega,eps,faintsun(icetime))
     print *,i,'of',SPINUPN,'  ',bigstep,zdepthP,omega/d2r
     do k=1,NP
        ! variables were evaluated at previous time step
        write(37,501) icetime,latitude(k),zdepthP(k), &
             & Tmean1(k),Tmean3(k),Tmin(k),Tmax(k)
     enddo
     omega = mod(omega + 36.*d2r,2*pi)  ! sweep
  enddo

  
  icetime = -(earliest-1)*timestep
  print *,icetime
  do 
     icetime = icetime + timestep
     call icelayer_asteroid(timestep,NP,thIn,z,porosity,.false., &
          & zdepthP,sigma,Tmean1,Tmean3,Tmin,Tmax,latitude,albedo, &
          & ecc,omega,eps,faintsun(icetime))
     do k=1,NP
        ! variables were evaluated at previous time step
        write(37,501) icetime,latitude(k),zdepthP(k), &
             & Tmean1(k),Tmean3(k),Tmin(k),Tmax(k)
        write(36,'(f12.0,2x,f7.3,2x)',advance='no') icetime,latitude(k)
        call compactoutput(36,sigma(1:nz,k),nz)
     enddo
     print *,icetime
     if (any(-icetime == (/ 4.498d9, 4.450d9, 4d9 /))) then
        timestep = 10.*timestep
     endif
     if (icetime>=0.) exit
     omega = mod(omega + 36.*d2r,2*pi)  ! sweep
  enddo

  close(34)
  close(36)
  close(37)

501 format (f12.0,2x,f7.3,2x,2x,f11.5,4(2x,f6.2)) 

end program asteroid_fast



subroutine outputskindepths(nz,z,zmax,porosity)
  ! diagnostics only
  use constants, only : pi, NMAX 
  use body, only : solarDay, solsperyear, Tnominal
  use allinterfaces
  implicit none
  integer, intent(IN) :: nz
  real(8), intent(IN) :: z(NMAX),zmax,porosity(nz)
  integer i
  real(8) delta, stretch, newrhoc, newti, rhoc
  real(8), dimension(nz) :: ti, rhocv, T, porefill
  real(8) :: thIn = 15.

  T = spread(Tnominal,1,nz)
  call assignthermalproperties(nz,thIn,T,porosity,ti,rhocv)
  rhoc = rhocv(1)
  porefill = 1.
  call assignthermalproperties(nz,thIn,T,porosity,ti,rhocv,porefill)
  newti = ti(1); newrhoc = rhocv(1)

  delta = thIn/rhoc*sqrt(solarDay/pi)
  stretch = (newti/thIn)*(rhoc/newrhoc)
  print *,'  dry skin depth - diurnal/seasonal',delta,delta*sqrt(solsperyear)
  do i=1,nz
     if (z(i)<delta) cycle
     print *,'  ',i-1,' grid points within dry diurnal skin depth'
     exit
  enddo
  print *,'  zmax=',zmax/(sqrt(solsperyear)*delta),'times seasonal dry skin depth'
  print *,'  zmax=',zmax/(sqrt(solsperyear)*delta*stretch),'times seasonal filled skin depth'
  write(*,'(3x,a,3(1x,f6.1))') 'Nominal thermal inertia extremes',thIn,newti
  if (i<=5) stop 'Not enough grid points'
end subroutine outputskindepths

