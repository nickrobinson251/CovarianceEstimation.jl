using CovarianceEstimation
using Statistics
using LinearAlgebra
using Test
using Random

const CE = CovarianceEstimation

include("reference_ledoitwolf.jl")

Random.seed!(1234)

const X  = randn(3, 8)
const Xa = randn(5, 5)
const Xb = randn(8, 3)
const Xc = randn(15, 20)
const Z = [2 -1 2; -1 2 -1; -1 -1 -1]
const X2s = [[1 0; 0 1; -1 0; 0 -1], [1 0; 0 1; 0 -1; -1 0]]

const test_matrices = [X, Xa, Xb, Z]

function testTransposition(ce::CovarianceEstimator, X)
    @test cov(X, ce; dims=1) ≈ cov(transpose(X), ce; dims=2)
    @test cov(X, ce; dims=2) ≈ cov(transpose(X), ce; dims=1)

    @test_throws ArgumentError cov(X, ce, dims=0)
    # XXX broken?
    # @test_throws ArgumentError cov(ce, X, dims=3)
end

function testUncorrelated(ce::CovarianceEstimator)
    for X2 ∈ X2s
        @test isdiag(cov(X2, ce))
    end

end

function testTranslation(ce::CovarianceEstimator, X)
    C1 = cov(X, ce)
    C2 = cov(X .+ randn(1, size(X, 2)), ce)
    @test C1 ≈ C2 atol = 1e-12 rtol = 1e-16
    C1t = cov(X', ce)
    C2t = cov(X' .+ randn(1, size(X, 1)), ce)
    @test C1t ≈ C2t atol = 1e-12 rtol = 1e-16
end

@testset "Simple covariance                  " begin
    sc = Simple()
    @test cov(X, sc; dims=1) ≈ cov(X; dims=1, corrected = false)
    @test cov(X, sc; dims=2) ≈ cov(X; dims=2, corrected = false)
    @test cov(X[1,:], X[2,:], sc) ≈ cov(X[1,:], X[2,:]; corrected = false)
    @test cov(X[1,:], sc) ≈ cov(X[1,:]; corrected = false)
    testTransposition(sc, X)
    testUncorrelated(sc)
    testTranslation(sc, X)

    sc = Simple(corrected=true)
    @test cov(X, sc; dims=1) ≈ cov(X; dims=1, corrected = true)
    @test cov(X, sc; dims=2) ≈ cov(X; dims=2, corrected = true)
    @test cov(X[1,:], X[2,:], sc) ≈ cov(X[1,:], X[2,:]; corrected = true)
    @test cov(X[1,:], sc) ≈ cov(X[1,:]; corrected = true)
    testTransposition(sc, X)
    testUncorrelated(sc)
    testTranslation(sc, X)
end


@testset "LinShrink: target F with LW        " begin
    lw = LinearShrinkageEstimator(ConstantCorrelation())
    testTransposition(lw, X)
    testUncorrelated(lw)
    testTranslation(lw, X)
    for X̂ ∈ test_matrices
        ref_results = matlab_ledoitwolf_covcor(X̂)
        lwfixed = LinearShrinkageEstimator(ConstantCorrelation(), ref_results["shrinkage"])
        @test cov(X̂, lw) ≈ ref_results["lwcov"]
        @test cov(X̂, lwfixed) ≈ ref_results["lwcov"]
    end
end


@testset "LinShrink: target ABCDE with LW    " begin
    # TARGET A
    lwa = LinearShrinkageEstimator(DiagonalUnitVariance())
    for X̂ ∈ test_matrices
        n, p = size(X̂)
        S = cov(X̂, Simple())
        Xtmp = copy(X̂); CE.centercols!(Xtmp)
        shrinkage  = CE.sum_var_sij(Xtmp, S, n)
        shrinkage /= sum((S-Diagonal(S)).^2) + sum((diag(S).-1).^2)
        shrinkage = clamp(shrinkage, 0.0, 1.0)
        @test cov(X̂, lwa) ≈ (1.0-shrinkage) * S + shrinkage * I
        lwafixed = LinearShrinkageEstimator(DiagonalUnitVariance(), shrinkage)
        @test cov(X̂, lwafixed) ≈ (1.0 - shrinkage) * S + shrinkage * I
    end
    # TARGET B
    lwb = LinearShrinkageEstimator(DiagonalCommonVariance())
    for X̂ ∈ test_matrices
        n, p = size(X̂)
        S = cov(X̂, Simple())
        Xtmp = copy(X̂); CE.centercols!(Xtmp)
        v = tr(S)/p
        F = v * I
        shrinkage  = CE.sum_var_sij(Xtmp, S, n)
        shrinkage /= sum((S-Diagonal(S)).^2) + sum((diag(S).-v).^2)
        shrinkage = clamp(shrinkage, 0.0, 1.0)
        @test cov(X̂, lwb) ≈ (1.0-shrinkage) * S + shrinkage * F
        lwbfixed = LinearShrinkageEstimator(DiagonalCommonVariance(), shrinkage)
        @test cov(X̂, lwbfixed) ≈ (1.0 - shrinkage) * S + shrinkage * F
    end
    # TARGET C
    lwc = LinearShrinkageEstimator(CommonCovariance())
    for X̂ ∈ test_matrices
        n, p = size(X̂)
        S = cov(X̂, Simple())
        Xtmp = copy(X̂); CE.centercols!(Xtmp)
        v = tr(S)/p
        c = sum(S-Diagonal(S))/(p*(p-1))
        F = v * I + c * (ones(p, p) - I)
        shrinkage  = CE.sum_var_sij(Xtmp, S, n)
        shrinkage /= sum(((S-Diagonal(S)) - c*(ones(p, p)-I)).^2) + sum((diag(S) .- v).^2)
        shrinkage = clamp(shrinkage, 0.0, 1.0)
        @test cov(X̂, lwc) ≈ (1.0-shrinkage) * S + shrinkage * F
        lwcfixed = LinearShrinkageEstimator(CommonCovariance(), shrinkage)
        @test cov(X̂, lwcfixed) ≈ (1.0-shrinkage) * S + shrinkage * F
    end
    # TARGET D
    lwd = LinearShrinkageEstimator(DiagonalUnequalVariance())
    for X̂ ∈ test_matrices
        n, p = size(X̂)
        S = cov(X̂, Simple())
        Xtmp = copy(X̂); CE.centercols!(Xtmp)
        F = Diagonal(S)
        shrinkage  = CE.sum_var_sij(Xtmp, S, n, false)
        shrinkage /= sum((S-Diagonal(S)).^2)
        shrinkage = clamp(shrinkage, 0.0, 1.0)
        @test cov(X̂, lwd) ≈ (1.0-shrinkage) * S + shrinkage * F
        lwdfixed = LinearShrinkageEstimator(DiagonalUnequalVariance(), shrinkage)
        @test cov(X̂, lwdfixed) ≈ (1.0-shrinkage) * S + shrinkage * F
    end
    # TARGET E
    lwe = LinearShrinkageEstimator(PerfectPositiveCorrelation())
    for X̂ ∈ test_matrices
        n, p = size(X̂)
        S = cov(X̂, Simple())
        Xtmp = copy(X̂); CE.centercols!(Xtmp)
        d = diag(S)
        F = sqrt.(d*d')
        shrinkage  = CE.sum_var_sij(Xtmp, S, n, false)-CE.sum_fij(Xtmp, S, n, p)
        shrinkage /= sum((S - F).^2)
        shrinkage = clamp(shrinkage, 0.0, 1.0)
        @test cov(X̂, lwe) ≈ (1.0-shrinkage) * S + shrinkage * F
        lwefixed = LinearShrinkageEstimator(PerfectPositiveCorrelation(), shrinkage)
        @test cov(X̂, lwefixed) ≈ (1.0-shrinkage) * S + shrinkage * F
    end
end


@testset "LinShrink: target B with RBLW+OAS  " begin
    rblw = LinearShrinkageEstimator(DiagonalCommonVariance(), :rblw)
    testTransposition(rblw, X)
    testUncorrelated(rblw)
    testTranslation(rblw, X)

    oas = LinearShrinkageEstimator(DiagonalCommonVariance(), :oas)
    testTransposition(oas, X)
    testUncorrelated(oas)
    testTranslation(oas, X)

    for X̂ ∈ test_matrices
        Ŝ_rblw = cov(X̂, rblw)
        Ŝ_oas  = cov(X̂, oas)

        CE.centercols!(X̂)
        n, p = size(X̂)
        Ŝ    = cov(X̂, Simple())

        F_ref = tr(Ŝ)/p * I
        # https://arxiv.org/pdf/0907.4698.pdf eq 17
        λ_rblw_ref = ((n-2)/n*tr(Ŝ^2)+tr(Ŝ)^2)/((n+2)*(tr(Ŝ^2)-tr(Ŝ)^2/p))
        λ_rblw_ref = clamp(λ_rblw_ref, 0.0, 1.0)
        # https://arxiv.org/pdf/0907.4698.pdf eq 23
        λ_oas_ref = ((1-2/p)*tr(Ŝ^2)+tr(Ŝ)^2)/((n+1-2/p)*(tr(Ŝ^2)-tr(Ŝ)^2/p))
        λ_oas_ref = clamp(λ_oas_ref, 0.0, 1.0)

        @test cov(X̂, rblw) ≈ CE.linshrink(Ŝ, F_ref, λ_rblw_ref)
        @test cov(X̂, oas) ≈ CE.linshrink(Ŝ, F_ref, λ_oas_ref)

        rblw_fixed = LinearShrinkageEstimator(DiagonalCommonVariance(), λ_rblw_ref)
        oas_fixed = LinearShrinkageEstimator(DiagonalCommonVariance(), λ_oas_ref)
        @test cov(X̂, rblw_fixed) ≈ CE.linshrink(Ŝ, F_ref, λ_rblw_ref)
        @test cov(X̂, oas_fixed) ≈ CE.linshrink(Ŝ, F_ref, λ_oas_ref)
    end
end

@testset "Analytical nonlinear shrinkage     " begin
    ans = AnalyticalNonlinearShrinkage()
    testTransposition(ans, Xc)
    testTranslation(ans, Xc)

    lwas1520 = [
        -1.162143666085967 0.9739741186960827 -2.140764943368969 -0.3003519954841573 -0.2320680292312552 -1.566581423746387 -0.08939530601705067 -0.9584822535011244 -0.579001012069752 -0.2748981243595355 0.7983963065161818 -1.041450869010109 -0.9978940199633209 2.248481624231867 0.889202720218581 -0.6574380822010187 0.236294375648874 -0.3691467373524263 0.05929723684648491 0.918714992101776
        0.1371803274891835 1.911125492699734 0.2525778419995699 1.098122949735456 0.07544845169678961 -0.7206794176595782 -1.093510251582698 -0.6693733432029153 0.06820846825708758 0.03507292011862988 0.1723265329109573 -0.7872056956813692 1.905477337628011 0.8366985512900044 0.5749341874041884 -1.679676872205402 -0.406296505279343 -1.368486032986794 0.3059672179777034 1.467739380455323
        -1.049930167731676 -0.5531994298464805 0.5437414633615258 0.2715098971120928 -0.2580106028662884 0.3168002684620484 1.226000586083078 -0.8115962615035417 -0.1035313091694913 -0.1462449428470634 -0.5981486545386802 -0.1743982986865505 0.9063848355320682 -0.8505300904610542 -0.2948314001511191 -1.634436014700057 0.1701167019815784 0.9034650542473315 0.2942912908036866 0.3383395154625917
        -0.8397847714027449 -1.023036710249146 -0.7642947001884048 -0.1389761098215158 -1.649844644088642 0.5300680589880117 0.2732614866894242 1.177534725584721 0.4901746349683212 -0.7217222373552608 1.125034198552572 -0.169774394492642 0.5349190857108541 0.9737808552629694 0.458816895109548 -1.183166454818553 -0.03192767125029861 -1.551767388422508 0.8938120577342226 0.7371582289227885
        -1.821817036923377 -0.1706655491675563 0.3903324984694236 -0.5114071568028367 2.498466086986865 -1.210419872514308 -0.9272632745436232 -0.3568949688753406 0.5498155335944914 1.732283512607968 0.4598082964601148 -0.29648966399001 0.1920866751800206 0.3807732360215121 0.2985509665423264 0.4913892907965938 0.002231365306557607 -0.6825716036874079 -0.8208300831927383 0.08319378517716935
        -0.1110540441386617 -0.5682283960456057 -0.3117878249903419 0.410093037211696 -1.24827329742475 0.6465216382282929 -0.9071526678630699 0.5863120782817395 1.306069001199071 1.176393817359979 0.4500234887609325 -1.216452344602953 1.03525585723392 0.5032128937805416 0.4714552093014561 -0.3296588311493343 0.0408519232299514 1.266319332420583 -2.389701958094318 -0.4293770947048847
        -0.3039749960547199 0.6424953351350216 -0.3855681522078479 -2.686077447950082 -0.9508396726633183 -0.476259711837803 -0.3182605629000175 0.4576940012896697 2.366645046168997 0.04401801778233076 0.5639647965453527 -0.5910242245474027 0.7465025534133467 1.924283233771143 -1.056582536048756 0.7222463197253957 -0.3619946819147883 -1.123292171331902 1.60933269987644 -0.9129926221695517
        -0.20749776064974 -0.06849065291434819 -1.768323246745156 -1.05492311894968 1.053990399274801 -0.05005310753005231 1.592718767063471 -1.496081216945174 -0.06265809845690011 0.460540110786074 0.6933842625257834 -0.2014843875101891 -1.715507829354832 -0.3718021611260288 0.07120409744804863 -0.8263461392085868 2.53822306968434 2.526150232063441 -0.03625921048203409 -1.487426700274362
        -1.804271348248873 -0.3685885790807754 0.6817778365658769 0.381808289079209 -1.253996105007014 0.3414911925530191 -1.166136562701281 0.862451123818788 -0.8666921637114556 -1.292470023645643 -0.6294855742408463 -0.6292311460336456 0.572868364134804 0.1736385568292795 0.9345038972249484 -1.388720320394404 0.2137090727670503 -0.5483270615035576 -0.6125129128358683 -0.1248664780585236
        -1.393762793937335 0.7875632596393551 -0.6761698886965171 0.2941724896233249 -1.813037485262276 1.481600646533385 -0.3006708420815597 -0.5752580147489298 -1.170637555116109 0.6783971935633739 0.1689073619836277 0.9795580809263011 -0.1405032688185065 0.3226513925575228 -0.4787177110433782 -0.184731118599034 0.1679005444988772 -2.157195368389053 -0.3349248240438316 0.3990080118946308
        1.541504211528512 2.939412347218787 -0.5245570622979617 -0.3356867550371349 0.1475139430010352 1.384611704782293 -1.061445256360972 -0.7502736328151003 -0.2578014662226829 0.6485099905283565 -0.1692441681399899 -0.504226526070725 -0.926434163660933 -0.32276719413933 -0.1802615807899683 -0.9122714589033599 -0.8405342524977313 0.5177927512279829 -0.7527142324787653 1.256954879582627
        0.4448370884363128 -1.347490013519331 0.8988585528478508 1.638553849616039 1.19200048018914 -0.1027436031312673 0.3647920398218376 -0.4118408133697098 -0.01141572227963682 1.254873808912089 2.18400950388516 -0.7813788821823292 0.02205352585343086 -0.3231124719736693 0.0907341391828073 0.4411151809382111 -0.4017746155475676 0.09431907429458543 -0.4796867813513169 -1.274775906389099
        -0.3811954384084654 1.881801496114762 0.3940362839186677 1.275573700657454 0.9073330974927114 -0.3437314725859643 -0.3136227920260322 0.00968553998243054 0.6197875241614621 -0.2295525852170562 1.433792421760441 -0.4407136933827355 0.2330131291958375 0.4719445439532242 -0.3648149737750805 -0.9627278874575644 0.1554385726360335 -0.4197012041754701 -1.025410623631298 0.336836795704037
        -0.1339340559991365 -1.03018422663586 -1.237536069913943 0.3455610034512538 0.5743102933342844 -0.2145373162356714 1.637584875373759 -0.3958411605430796 -1.463134166162239 1.054266803463341 -0.5838076500823989 -0.8458688808111442 -0.3583966917242682 -1.331446431469177 -1.158173294258694 -0.5011333046185092 -0.258580459588638 1.283514084166021 0.2558835132552651 0.7449009145129694
        -0.06210189923259225 0.4700076795381495 -1.573703973459995 -0.02120317598383387 -0.425410300707993 0.6653697422657228 0.08843341113293361 1.126147366217366 0.9538145275617389 -0.2224921907495701 -0.5966853888824428 0.03101944218706047 0.445857850594245 0.01222541202335255 1.167856391151787 -1.201625830595669 0.4551719534146649 -1.534703795301182 -0.4007255005254743 1.35518609510561]
    lwas1520S = [
        3.795757712652756e-15 -2.318456313511018e-15 2.157558246151186e-15 -1.65220674208211e-15 -1.694638437599841e-16 -2.243640680141986e-15 2.195842932397521e-16 -4.263392914142881e-16 -1.211502523427402e-15 -1.128591563998871e-15 -8.794533735884679e-16 2.913292337381372e-15 -4.356951031568335e-16 2.259702549697162e-15 -1.68551743287697e-15 -5.46773489791153e-16 1.422176492495236e-15 -7.450052772306979e-16 -2.911732787467458e-15 1.417374358791011e-15
        -2.318456313511018e-15 3.438347659767201e-15 2.176091705618497e-16 -2.389861997383063e-16 -9.234307024127878e-16 1.867569858756357e-16 2.255873887444063e-15 2.579625578779943e-15 -1.007209406351251e-15 2.404720289945406e-15 1.364069560314883e-15 -9.307686435738615e-16 9.927121580889053e-16 -1.427914748611245e-15 3.213316268479059e-15 9.020427494034013e-16 -9.548626905650719e-16 1.260835397350813e-15 1.710482558216452e-15 -9.027258618208092e-16
        2.157558246151186e-15 2.176091705618496e-16 5.12054371312724e-15 -9.258200330629281e-16 -1.909799055902799e-15 -1.737708668040011e-15 2.55199151147277e-15 1.742699836330742e-15 -1.000313267871381e-15 2.382473599794456e-15 -1.044577770867846e-15 -8.292111807656527e-16 -2.143156607163469e-15 1.93814187190685e-15 4.420580344215942e-16 7.261473229029189e-16 3.854394130073714e-15 -6.251118518154118e-16 -6.767781710832801e-16 2.682474890745508e-15
        -1.65220674208211e-15 -2.389861997383061e-16 -9.258200330629281e-16 4.99729592655002e-15 3.428538435800226e-16 1.410287957344125e-15 -2.861508032833094e-15 4.8826814730421e-16 2.879216850824162e-15 1.020659242988209e-15 -2.449676335094376e-15 8.677134076467862e-16 -2.376294721152545e-15 1.427535090057778e-15 -5.990712720030503e-16 6.747376772943779e-16 2.490343037540962e-16 2.125896484520616e-15 4.318812580591526e-15 -2.498757934558681e-17
        -1.694638437599841e-16 -9.23430702412788e-16 -1.909799055902799e-15 3.428538435800227e-16 3.492258523753305e-15 4.081606418727934e-15 1.511625927365745e-16 -6.34770070520928e-16 -1.001419952963964e-15 -1.770203481675085e-15 -9.190904601715871e-16 -3.35849924001522e-16 2.189140265187109e-15 3.550402544943517e-15 -1.093910002607325e-15 -2.202660296090785e-16 -1.078982547589802e-15 1.844641682738732e-16 -4.120730899298837e-16 -1.142621103863586e-15
        -2.243640680141986e-15 1.867569858756357e-16 -1.737708668040011e-15 1.410287957344125e-15 4.081606418727933e-15 7.201036196091142e-15 8.325178594767828e-16 -6.285756865207549e-16 -4.651567794770427e-16 -1.215804547786442e-15 -9.735471207302737e-16 -4.463048368424733e-15 2.262658708779433e-15 3.642669587156058e-15 -3.951074181157763e-16 1.472643960009367e-15 2.993595024159464e-16 1.945079433814312e-16 1.407180288249029e-15 -3.728179437617745e-16
        2.195842932397519e-16 2.255873887444063e-15 2.55199151147277e-15 -2.861508032833094e-15 1.511625927365745e-16 8.325178594767829e-16 4.866918392716886e-15 2.530358862555848e-15 -3.224626991369649e-15 2.325225033140847e-15 6.840233669223914e-16 -2.037907694760315e-15 1.449031784454501e-15 1.86839247629534e-15 2.109246757586933e-15 -4.591881480151486e-16 4.848844667706404e-16 -7.34425193284975e-16 -1.510410045479217e-15 -3.89350708175063e-16
        -4.263392914142879e-16 2.579625578779943e-15 1.742699836330742e-15 4.882681473042098e-16 -6.34770070520928e-16 -6.285756865207548e-16 2.530358862555848e-15 3.90252763252789e-15 -1.585049223387818e-15 3.298032099809426e-15 -5.478777715330255e-16 2.009120914081841e-15 -2.510349799745708e-17 2.009661979947726e-15 2.52570365653227e-15 1.023658161588214e-17 -5.182566765376607e-16 1.966777172757703e-15 1.55495809902957e-15 -8.467469198117481e-16
        -1.211502523427402e-15 -1.007209406351251e-15 -1.000313267871381e-15 2.879216850824162e-15 -1.001419952963964e-15 -4.651567794770431e-16 -3.224626991369649e-15 -1.585049223387818e-15 3.530880667333913e-15 3.153116668788999e-16 -9.703670481372442e-16 -1.221496593185809e-15 -2.970297456162829e-15 -2.041616656188348e-15 -1.407039130583873e-15 -6.905844893203649e-16 4.112670181443823e-16 -3.733150238276201e-16 2.185977457114104e-15 1.328035315220752e-16
        -1.128591563998871e-15 2.404720289945406e-15 2.382473599794456e-15 1.020659242988209e-15 -1.770203481675085e-15 -1.215804547786442e-15 2.325225033140847e-15 3.298032099809427e-15 3.153116668788997e-16 5.510022129767997e-15 -1.249079841547842e-15 -1.27894401806272e-15 -2.972881628803614e-15 7.623000518843187e-16 1.6317278958734e-15 -2.960093585836899e-15 -1.015299423115166e-16 -2.588842140338193e-16 1.866590753608416e-15 -1.678059118437673e-15
        -8.794533735884679e-16 1.364069560314883e-15 -1.044577770867846e-15 -2.449676335094376e-15 -9.190904601715871e-16 -9.735471207302733e-16 6.840233669223913e-16 -5.478777715330254e-16 -9.703670481372444e-16 -1.249079841547842e-15 3.002451957883479e-15 -6.940705390275977e-16 2.283199559474117e-15 -3.972455238119486e-15 1.655241830245106e-15 1.439181048251861e-15 -9.42279376602671e-16 -1.86046635127761e-16 -1.131568188899943e-15 9.993719193801575e-17
        2.913292337381372e-15 -9.307686435738615e-16 -8.292111807656527e-16 8.677134076467862e-16 -3.35849924001522e-16 -4.463048368424733e-15 -2.037907694760315e-15 2.009120914081842e-15 -1.221496593185809e-15 -1.27894401806272e-15 -6.940705390275975e-16 1.108794790758089e-14 9.886205938370125e-16 1.85385663811485e-15 2.190054918621233e-16 4.854787301413994e-16 -2.614229437323993e-15 3.943344101927354e-15 -1.518375024921146e-16 -6.316019821602348e-16
        -4.356951031568336e-16 9.927121580889053e-16 -2.143156607163469e-15 -2.376294721152545e-15 2.189140265187109e-15 2.262658708779433e-15 1.4490317844545e-15 -2.510349799745727e-17 -2.970297456162829e-15 -2.972881628803614e-15 2.283199559474117e-15 9.886205938370123e-16 5.128036680620842e-15 1.182916708842332e-16 1.493915735683011e-15 2.548566832193486e-15 -1.775491804281254e-15 1.230311688438517e-15 -1.477297056424067e-15 -3.797913217748978e-16
        2.259702549697162e-15 -1.427914748611245e-15 1.93814187190685e-15 1.427535090057779e-15 3.550402544943517e-15 3.642669587156058e-15 1.86839247629534e-15 2.009661979947727e-15 -2.041616656188348e-15 7.623000518843187e-16 -3.972455238119486e-15 1.85385663811485e-15 1.182916708842332e-16 9.142549954830602e-15 -1.507030200987064e-15 -8.725593409579203e-16 1.09825179994025e-15 9.467347589532932e-16 -1.221508140208094e-16 -1.895451272202691e-16
        -1.68551743287697e-15 3.21331626847906e-15 4.420580344215942e-16 -5.990712720030503e-16 -1.093910002607325e-15 -3.951074181157761e-16 2.109246757586934e-15 2.52570365653227e-15 -1.407039130583873e-15 1.6317278958734e-15 1.655241830245106e-15 2.190054918621229e-16 1.493915735683011e-15 -1.507030200987064e-15 3.306608831165425e-15 1.90032323643512e-15 -6.452629702969675e-16 1.727088861604761e-15 1.337125376460652e-15 -1.812118228028831e-16
        -5.467734897911528e-16 9.020427494034013e-16 7.261473229029189e-16 6.747376772943779e-16 -2.202660296090785e-16 1.472643960009367e-15 -4.591881480151488e-16 1.023658161588214e-17 -6.905844893203647e-16 -2.960093585836899e-15 1.439181048251861e-15 4.854787301413996e-16 2.548566832193486e-15 -8.725593409579205e-16 1.90032323643512e-15 7.949572043021779e-15 3.06727192806477e-15 3.210130018942367e-15 1.867878428629047e-15 4.542920081283084e-15
        1.422176492495236e-15 -9.548626905650719e-16 3.854394130073714e-15 2.490343037540962e-16 -1.078982547589802e-15 2.993595024159462e-16 4.848844667706402e-16 -5.182566765376609e-16 4.112670181443823e-16 -1.015299423115168e-16 -9.42279376602671e-16 -2.614229437323994e-15 -1.775491804281254e-15 1.09825179994025e-15 -6.452629702969675e-16 3.067271928064769e-15 5.054491936245635e-15 -5.488338689006637e-16 1.199057028140736e-16 4.256934017539456e-15
        -7.450052772306977e-16 1.260835397350813e-15 -6.251118518154118e-16 2.125896484520616e-15 1.844641682738732e-16 1.945079433814313e-16 -7.344251932849752e-16 1.966777172757703e-15 -3.733150238276203e-16 -2.588842140338197e-16 -1.860466351277609e-16 3.943344101927354e-15 1.230311688438517e-15 9.467347589532932e-16 1.72708886160476e-15 3.210130018942367e-15 -5.488338689006637e-16 3.725630058847267e-15 2.64641960377633e-15 5.309607235265456e-16
        -2.911732787467458e-15 1.710482558216452e-15 -6.767781710832802e-16 4.318812580591526e-15 -4.120730899298837e-16 1.407180288249029e-15 -1.510410045479217e-15 1.55495809902957e-15 2.185977457114104e-15 1.866590753608416e-15 -1.131568188899943e-15 -1.51837502492115e-16 -1.477297056424067e-15 -1.221508140208097e-16 1.337125376460652e-15 1.867878428629047e-15 1.199057028140741e-16 2.64641960377633e-15 4.929921609246131e-15 3.513799405323772e-17
        1.417374358791011e-15 -9.027258618208092e-16 2.682474890745508e-15 -2.498757934558681e-17 -1.142621103863586e-15 -3.728179437617744e-16 -3.89350708175063e-16 -8.467469198117482e-16 1.328035315220752e-16 -1.678059118437673e-15 9.993719193801561e-17 -6.316019821602348e-16 -3.797913217748977e-16 -1.895451272202689e-16 -1.812118228028832e-16 4.542920081283084e-15 4.256934017539456e-15 5.309607235265455e-16 3.513799405323762e-17 4.511005026884609e-15]

    lwas2015 = [
        -0.485318091300385 -0.4646528957025956 0.7127436158932768 -0.3794206904568262 1.213013666610619 1.328169750623183 -1.811232382718297 -0.05606420458264962 -0.3339634722560829 1.605096962107702 -0.845139590907237 0.2565222123830785 -0.6483072914710626 -1.277926528579344 0.8103933816353912
        -0.5476205061621616 -1.499815641826814 -0.1963498578907385 0.4073215488657893 1.585696216038667 1.00952189473736 1.163930788843176 -0.5821749802084811 0.02563216436672771 -0.7001257075246631 0.003982634154081411 -0.4494719560808281 1.197225574808631 1.466576182440341 -0.09284378124097199
        -0.5222702112062024 -0.7362427594390911 -0.1326010918451699 -1.863887784574423 -0.2261544975204104 -0.635411155259718 0.2366377560593635 -0.7482066955123203 0.3646029395611501 -1.598087870076572 -0.7044945852364686 -0.3452679101647944 -0.7806461313434916 -1.106230641004722 -1.948072556569429
        -0.4005183923065789 -0.002310897523432088 0.496772721264171 -0.7610922934909876 0.2473593343912224 0.2212302756187546 1.106266152071804 -2.146265865631319 0.44982045317356 -0.1938846119833013 0.3885682703097711 0.6790098047292304 0.2238813186834151 -1.019852240499034 -0.2459033421329224
        -0.4863515457327924 -0.8667264445682425 0.2059222003898268 1.178889076964668 -0.4571069655509472 -1.297574001933576 -1.64237624781427 -1.26534103456894 0.9525927328450224 -0.1908799256634049 -0.04866260458324331 -0.08346145644934959 -2.395046553483935 -0.253788745027382 -0.9875476177751877
        1.07416301969567 0.4232217450605181 -0.007622987470516999 -0.8708994158117607 -1.516678131842789 -0.02525843843468113 -0.5627444381880664 -0.1880331618982527 1.040677826296151 -0.4976943680968737 1.381576430105507 -0.5360353457949458 0.3122679122645717 0.3000025877812805 -0.3755431248140295
        0.2025137094620404 0.6596478555388814 -1.106812320557654 -2.111400775026922 -1.765884374633444 -0.4016022286651444 -0.3872311745648876 0.2556025475076431 -0.81869767524774 -0.4022900589724391 0.4098406559877635 1.614773012410563 0.01127735399546741 0.7251396271870196 0.1714811712122369
        0.8096406253389377 1.230596565362862 -0.2177711965042983 -1.178460195555342 1.240439361823165 1.682473541484175 0.1932725975263187 0.5592565566752462 -0.03389657354824809 -0.56032730130221 -0.2566039899013353 0.4871119998480957 0.3322066849265872 -0.3356250114897751 -0.1450182191335252
        -1.04791537349489 1.154926931875593 0.7836861457645294 0.6242934081216347 -0.8403462060900335 0.1892509036218717 0.5411622100714343 0.6933275350706701 1.464361835204958 1.40650969841594 0.5578823172280858 0.2761050319828439 0.6895357475411432 0.9305041200012252 0.5214253537733887
        -0.5490176621724966 1.209225348262831 -0.2162506579968914 -0.3570406538934983 -0.666125620727431 0.4446824968019705 0.6640442465302624 0.1836252137681993 -0.6621048591919108 -1.406422331868054 -0.5733257771014584 -0.5997516325912073 -2.079925901061282 -0.607849338554422 -0.4409536215718879
        -0.1583943573479144 0.4951048091587314 -1.125096784312634 -0.8572611236477092 0.5510170401133744 0.3144793250947476 -1.644248898222228 0.7449598096529678 -1.021896911552751 -1.486020679278579 -0.5206800771942667 -1.437960337904433 -0.948858508067345 0.185916829645591 1.310515690749875
        -0.09891981814461216 -1.140183305492252 0.1383042460164424 1.703920288435306 -0.2316304941321169 1.565759888700433 1.362318644229116 -0.218920555762152 -0.826876004653973 -0.5429640046832165 -0.8414486113860139 -0.4269144612014189 1.257980719097372 2.591686269618937 0.2085996418289362
        1.37909866902478 -0.1738898598297275 -0.9821302739150887 0.007434261248696324 0.4158743282948477 1.539234626491651 1.267464774740194 -0.6693622314229509 0.1762361269672286 -0.207843094954978 -0.4191024055902136 -1.129207208621555 0.1179258481683548 1.212809104084617 -2.24391659257257
        -0.03609685181688043 2.277909194636921 0.03319333316783139 0.6640986586015488 0.7519362463997421 -0.2537463298216008 -0.8671209623550391 0.2484006470997926 0.2735323555301608 -0.46898935937476 -0.0973634830024568 1.081474834475504 0.0719017791170663 0.8841331543367712 0.4458281739542139
        0.8046804404738693 0.1264818241226116 0.05785628924077314 0.7629691511863583 1.01006744387435 1.069748280592117 1.18613488112882 -0.3407302666123762 0.495922456458428 0.1475890304739086 -0.8571872684575019 0.9936526259653155 -0.7501300062074486 0.974678902854181 0.6029735383493137
        1.592723052297395 0.3715640002824156 -1.657728383139588 0.513114839260094 -0.2542389309678127 0.3782944694338278 -0.7829472775983846 0.8132518461404652 -0.4198916342657842 1.227635587959188 -0.2502433263627895 0.2028700563503304 -1.105390366317186 0.9792147324817624 0.4571221958582657
        -0.6495384763343833 -1.471842192430597 -0.8930928860585181 0.4795544766943093 0.2608158937156739 0.9275902732718317 -0.3850430016739592 -0.02008357914397888 -0.02741789598849841 -0.08411658846467432 -0.8100227779808953 1.472884693705241 1.162992049265734 -0.6887743943890233 1.286040382562623
        0.1131428278467076 -0.825276832906783 0.6740669940102881 -0.2787118900629319 0.6748584847882704 0.2388597120274148 -0.143996557912974 0.3384083618430931 -0.569919388712617 -1.11786350680029 -0.4898907174670241 1.455505973288721 0.1177341548295516 -1.363446875990347 -0.2279145718422189
        -0.2209387938130484 -1.839201982232933 0.2113279833190781 -0.7541287918210327 1.049699660038909 1.808388460860524 0.2814602803699362 -1.614118848666635 -0.4414924796726503 -1.575144831297377 0.5473591406848032 0.1313463940792598 0.1286706424883373 1.19074188596207 -0.6561733379368632
        0.6723945551117826 -0.7445493404020891 -1.097897753533755 -0.2702049762091814 1.223205235543511 -0.1616151761376242 -1.313161932613551 0.09787818416995887 0.1734863210339769 -2.177386466445702 0.8360896683543493 -0.2253487231841086 1.731377477901027 -0.5695636242307396 -2.469523709404596]
    lwas2015S = [
        0.6325550512139276 0.04352737905344341 -0.1131950439176197 -0.00182221455229032 0.04045180874834752 0.04606816640707907 -0.01254881715313673 -0.01660978281011054 -0.009950748594896934 0.01180857850540902 0.05098453124936327 0.07476304189502121 -0.03946519779797149 0.07659154789231884 -0.07564795573771382
        0.04352737905344341 0.8230073361107487 0.02190768209436339 -0.0601144882908185 -0.03803867851775322 -0.08330298066866598 -0.05690866676477252 0.1204869463963438 0.05785580644413245 0.04164504030425251 0.04481473023333406 0.05111811163520005 -0.1333926417257547 0.009080697648945368 0.102633222475419
        -0.1131950439176197 0.02190768209436336 0.5738739938309639 0.0128559452606075 0.04698962244522378 0.04431481225376206 0.02900736523001539 -0.0840940024602919 0.06255321380357734 0.03135416663818182 0.05487758081232082 0.006911594870147145 -0.007699333766680957 -0.02012594552721209 0.0400858064569651
        -0.00182221455229031 -0.0601144882908185 0.01285594526060752 0.7896957538542808 0.05336394720635625 -0.01272899472916082 0.0875115980609133 0.07959324603301463 0.04208208098587068 0.07534661492997122 -0.1190873483555072 0.02542930971540588 0.0456396780726888 0.1317265240473271 0.03076085045285286
        0.04045180874834752 -0.03803867851775319 0.04698962244522376 0.0533639472063562 0.7760434722473366 0.1316308703216585 -0.02116201043573809 -0.1285051505351066 -0.0309509057566479 -0.07947771863562389 0.01784314908051052 0.03755977871688025 0.04458080660654506 0.05305831476006392 0.003850601626765184
        0.04606816640707904 -0.08330298066866598 0.04431481225376203 -0.01272899472916084 0.1316308703216585 0.673144564383644 0.1329245264179616 -0.0270559453937091 -0.03864113934878405 0.07224023881487006 -0.05624793185393113 -0.08994552888764216 0.1228507742928865 0.1189371310116167 0.07032893316620591
        -0.01254881715313673 -0.05690866676477249 0.0290073652300154 0.08751159806091327 -0.02116201043573809 0.1329245264179615 0.8398219059354901 -0.01739610146771776 -0.01574839206664143 -0.0101728285687615 -0.09920393773487274 -0.005333626191211589 0.1382516421067967 0.09050700222677191 -0.0893265103792264
        -0.01660978281011057 0.1204869463963438 -0.0840940024602919 0.07959324603301463 -0.1285051505351066 -0.0270559453937091 -0.01739610146771776 0.7408908015291807 -0.05729949709942531 0.09364492567805167 -0.1424705851568909 -0.07061711777000201 0.0924940469996247 -0.1245886548586114 0.03387673325116507
        -0.00995074859489692 0.05785580644413246 0.06255321380357731 0.04208208098587066 -0.0309509057566479 -0.03864113934878403 -0.01574839206664141 -0.0572994970994253 0.5556414405604636 0.07628663821132585 0.04988003523682134 -0.02453534611164747 0.04303406791591439 -0.02901182120500938 -0.05928614389663873
        0.01180857850540899 0.04164504030425251 0.03135416663818183 0.07534661492997125 -0.07947771863562389 0.07224023881487004 -0.01017282856876151 0.09364492567805165 0.07628663821132586 0.8091055362504933 -0.02873717108320658 -0.001721283795671864 -0.01293262027303935 -0.005335584311624168 0.1426115019315111
        0.05098453124936327 0.04481473023333407 0.05487758081232081 -0.1190873483555072 0.0178431490805105 -0.05624793185393114 -0.09920393773487268 -0.1424705851568909 0.04988003523682132 -0.02873717108320659 0.6421072182128197 -0.007680192093628248 0.04075008117381045 0.1014195326513618 0.008752743952130267
        0.07476304189502125 0.05111811163520005 0.006911594870147147 0.02542930971540591 0.03755977871688027 -0.08994552888764221 -0.005333626191211589 -0.07061711777000201 -0.02453534611164751 -0.00172128379567185 -0.007680192093628248 0.8286713029126824 -0.01142253452615733 0.00381921289707525 0.09876459368709081
        -0.03946519779797151 -0.1333926417257547 -0.007699333766680954 0.0456396780726888 0.04458080660654504 0.1228507742928865 0.1382516421067967 0.09249404699962469 0.04303406791591435 -0.01293262027303933 0.04075008117381045 -0.01142253452615737 0.8353020926453681 0.05693700192781775 -0.04571471796917492
        0.07659154789231884 0.009080697648945368 -0.02012594552721209 0.1317265240473271 0.05305831476006392 0.1189371310116167 0.09050700222677199 -0.1245886548586114 -0.02901182120500936 -0.005335584311624168 0.1014195326513618 0.003819212897075312 0.05693700192781778 0.8847070821221401 0.1035703411843826
        -0.07564795573771382 0.1026332224754189 0.04008580645696509 0.03076085045285281 0.003850601626765184 0.07032893316620592 -0.0893265103792264 0.03387673325116502 -0.05928614389663873 0.1426115019315111 0.008752743952130267 0.0987645936870908 -0.04571471796917492 0.1035703411843826 0.8024885329019101]
    lwas2015λ = [
        0.05896863579915038
        0.06955122254090784
        0.1097500668748013
        0.1628238843671115
        0.1818997338393973
        0.3533043354954716
        0.4676092641418833
        0.5865831295444397
        0.7294925747514915
        0.8916663580040058
        1.084225651809171
        1.225938398716431
        1.452145896042682
        2.152059618728669
        2.359120103265717]
    lwas2015u = [
        -0.02111732781090808 -0.405124930615285 0.1228684142347386 -0.4577304314718168 -0.1881609541881636 -0.1684629775351973 -0.2209199224396676 0.4738381348192535 -0.3274501563162528 0.07520603916328307 -0.06664352141049927 -0.2448544673790787 -0.3094156032336442 0.002897425627194574 -0.02608661319589035
        0.08923328492708922 -0.02841352830501796 -0.3559939784546138 0.06791777358184038 0.0742568029194722 -0.1288068879481518 -0.02142041423720173 -0.3918544214049002 -0.3999605548914586 -0.2983125776063134 0.1898883878226054 -0.1162970514412131 -0.3969637090283756 0.3019659729479048 0.3694136816467629
        -0.04455052214905159 -0.3715581033384094 0.1565978382064118 -0.003191031292153975 -0.6775899219414636 -0.09095095250972217 0.2064724315497899 -0.2682185500026188 -0.1242311046692326 -0.1592012460182128 0.1531858150594013 0.3602942811291428 0.2379931443132557 0.03700655694878963 -0.037256389054032
        -0.08319816733099984 0.1422455778853745 -0.3077828032304233 -0.2880192006895443 -0.09975529350478049 0.1529225520802654 -0.3786659946225196 -0.2801308917315645 -0.1477597344744272 0.3977776076244992 -0.3155667890674026 0.2844255572610216 0.06238698764776182 0.334745817763862 -0.2519406876800819
        -0.2497111164200597 -0.01941737813009289 0.2221556971251099 0.1986870439997734 0.2555414520135609 -0.3175065841759729 -0.02677900913146626 -0.2163696874876608 -0.5384171769886897 -0.007185973487374655 -0.1651135510358665 -0.291391721044485 0.3975727445559162 -0.07723744625620854 -0.2620053091449628
        0.3687056050749488 0.4732714008077814 -0.2033912632892204 -0.1391788961384178 -0.3065936957779404 -0.002874279045301357 0.2964048173829246 0.2034640890681186 -0.1550429047781079 -0.3033886542123417 -0.07687312316491186 -0.2540469294592335 0.1089877835085187 0.1328011006800581 -0.3741970245961272
        -0.3210916001788964 0.02530774536829952 0.1620282350872316 -0.145634080768713 0.2180503964997064 0.2389871062321949 -0.2096583523735262 -0.004260079639756343 0.01050826594561104 -0.5990747493307228 0.1828063998406034 0.2525641967895592 -0.2090526205068587 0.02513109636711988 -0.4467877349567394
        -0.1679408621986317 0.2207551157014802 0.5098400171858662 0.09014419266262169 -0.2872130931707642 0.5084896344202328 -0.06865132903498225 -0.1553559392319616 -0.04377802051219316 0.1021772127485199 0.01748120050034177 -0.410320010012715 -0.1186743045544992 0.2530207372358754 0.1611545846713704
        0.5136496100555989 0.174232473292157 0.47867139712452 -0.1970187483563824 0.2746402345648987 0.01480353375011488 0.1168313290904389 -0.04955911938444332 -0.329123000038575 0.1978789738406655 0.2012114287466069 0.3895628582600864 -0.07376190250270667 0.004885295637289935 0.03040360958327427
        -0.2421865262391815 -0.06899316545347278 -0.09514885770340115 0.3374825922225113 0.1152926844136012 0.1669801746418687 0.2663495699625685 0.5311566888977599 -0.2535885539148989 0.09033614170597774 0.0520264409449182 0.2595678242060955 0.1053580460452721 0.5118110725312207 0.06158449596392203
        -0.5422315875427588 0.4535476866968873 -0.007734561121473116 -0.2444027163098785 -0.1093903903357574 -0.3587217260311079 0.2861277377213817 -0.00770235220077443 -0.004350661779163094 0.2510153595815636 0.3008804834670543 0.073527118808442 -0.2139347015872398 -0.1094298832234447 0.03471383036931747
        0.1095125232823221 0.2301163606628587 0.04194930691947463 0.1687981811146199 -0.1540335393323366 -0.2933925545536684 -0.6418178100874725 0.1977895536539791 0.07264732257915536 -0.03123932054331107 0.475367489819122 0.0005420774861562264 0.2803923851996754 0.1642830601491472 0.07815164702874564
        0.08437165913907607 -0.2858505263260866 -0.2320373124100325 0.01325096682597895 0.08722090713068303 0.2431136959632471 0.1201078255319929 -0.1210813025302011 -0.00500487139385266 0.3462588931077566 0.6199246433442533 -0.2784818022434174 0.0119356131112842 -0.02323700813091725 -0.4229589874580539
        0.1311885021292079 -0.06609333359484194 0.2142067058691495 0.4037497692723672 -0.071552565104472 -0.4027374859186953 0.0218156559262466 -0.07808145299604483 0.2540797305115163 0.1373042132891731 -0.1557010845190202 0.009384419494445921 -0.4792492716833969 0.304300856893897 -0.4069572992897037
        -0.0159392231209386 -0.1522700548717422 0.149272719648131 -0.4589077823487346 0.2520400580820472 -0.2066703837721567 0.1848825122629494 -0.1209337448694974 0.3702379260247126 -0.1015163204611454 0.03621489282260958 -0.1789689050034709 0.2960886805234728 0.5595121572318335 0.08480735933411085]
    #@test cov(lwas1520, ans) ≈ lwas1520S
    @test cov(lwas2015, ans, decomp = Eigen(lwas2015λ, lwas2015u)) ≈ lwas2015S
end
