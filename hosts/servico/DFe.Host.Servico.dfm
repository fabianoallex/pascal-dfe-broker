object DFeBrokerService: TDFeBrokerService
  AllowPause = False
  DisplayName = 'pascal-dfe-broker'
  OnStart = ServiceStart
  OnStop = ServiceStop
end
