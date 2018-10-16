/// This file is generated by Weaver 0.10.3
/// DO NOT EDIT!
import API
import Foundation
import UIKit
// MARK: - HomeViewController
protocol HomeViewControllerInputDependencyResolver {
    var movieManager: MovieManaging { get }
    var imageManager: ImageManaging { get }
    var reviewManager: ReviewManaging { get }
}
protocol HomeViewControllerDependencyResolver {
    var movieManager: MovieManaging { get }
    var logger: Logger { get }
    func movieController(movieID: UInt, title: String) -> UIViewController
}
final class HomeViewControllerDependencyContainer: HomeViewControllerDependencyResolver {
    let movieManager: MovieManaging
    let imageManager: ImageManaging
    let reviewManager: ReviewManaging
    private var _logger: Logger?
    var logger: Logger {
        if let value = _logger { return value }
        let value = Logger()
        _logger = value
        return value
    }
    private weak var _movieController: UIViewController?
    func movieController(movieID: UInt, title: String) -> UIViewController {
        if let value = _movieController { return value }
        let dependencies = MovieViewControllerDependencyContainer(injecting: self, movieID: movieID, title: title)
        let value = MovieViewController(injecting: dependencies)
        _movieController = value
        return value
    }
    init(injecting dependencies: HomeViewControllerInputDependencyResolver) {
        movieManager = dependencies.movieManager
        imageManager = dependencies.imageManager
        reviewManager = dependencies.reviewManager
        _ = logger
    }
}
extension HomeViewControllerDependencyContainer: MovieViewControllerInputDependencyResolver {}