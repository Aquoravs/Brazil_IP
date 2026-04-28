# First Stage — Multiple Instruments (cycle-specific, muni×year FE, party)

                                           M+G               M+P
Dependent Var.:                    delta_s_mjt       delta_s_mjt
                                                                
Z_mayor_party_cycle_specific          0.0454**          0.0480**
                                     (0.0164)          (0.0169) 
Z_gov_party_cycle_specific           -0.0266**                  
                                     (0.0098)                   
Z_pres_party_cycle_specific                             0.0611* 
                                                       (0.0348) 
Fixed-Effects:                     -----------       -----------
muni_id-cnae_section                       Yes               Yes
muni_id-year                               Yes               Yes
____________________________       ___________       ___________
S.E.: Clustered              by: muni. & cnae. by: muni. & cnae.
Observations                         1,372,575         1,372,575
R2                                     0.03692           0.03692

                                         M+G+P
Dependent Var.:                    delta_s_mjt
                                              
Z_mayor_party_cycle_specific          0.0459**
                                     (0.0168) 
Z_gov_party_cycle_specific           -0.0239**
                                     (0.0097) 
Z_pres_party_cycle_specific           0.0578  
                                     (0.0359) 
Fixed-Effects:                     -----------
muni_id-cnae_section                       Yes
muni_id-year                               Yes
____________________________       ___________
S.E.: Clustered              by: muni. & cnae.
Observations                         1,372,575
R2                                     0.03693
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
